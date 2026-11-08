// Executes the real migration in an in-process Postgres (PGlite) with a minimal
// Supabase stub (auth.users, auth.uid(), roles) and checks the access rules.
// Run: npm install && npm test   (from supabase/tests)
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

const migration = readFileSync(new URL("../migrations/0001_core.sql", import.meta.url), "utf8");
const db = new PGlite();
const ids = {};

const STUB = `
  create role anon nologin;
  create role authenticated nologin;
  create schema auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;
`;

const GRANTS = `
  grant usage on schema public to anon, authenticated;
  grant select, insert, update, delete on all tables in schema public to authenticated;
`;

async function admin(sql, params) {
  await db.query("reset role");
  await db.query("select set_config('request.jwt.claim.sub', '', false)");
  return db.query(sql, params);
}

async function as(user, sql, params) {
  await db.query("reset role");
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [ids[user]]);
  await db.query("set role authenticated");
  try {
    return await db.query(sql, params);
  } finally {
    await db.query("reset role");
  }
}

async function signup(name) {
  const r = await admin("insert into auth.users (email) values ($1) returning id", [`${name}@example.com`]);
  ids[name] = r.rows[0].id;
}

const rejects = (promise, code) => assert.rejects(promise, (e) => e.message.includes(code));

before(async () => {
  await db.exec(STUB);
  await db.exec(migration);
  await db.exec(GRANTS);
  await admin("insert into public.app_config (owner_email) values ('owner@example.com')");
  await admin("insert into public.invites (email) values ('anna@example.com'), ('bert@example.com')");
  await signup("owner");
  await signup("anna");
  await signup("bert");
});

test("signup is invite only", async () => {
  await rejects(admin("insert into auth.users (email) values ('stranger@example.com')"), "not_invited");
});

test("owner is assigned from app_config, others are members", async () => {
  const r = await admin("select email, role from public.profiles order by email");
  assert.deepEqual(
    r.rows.map((x) => [x.email, x.role]),
    [["anna@example.com", "member"], ["bert@example.com", "member"], ["owner@example.com", "owner"]],
  );
});

test("members cannot manage invites", async () => {
  await rejects(as("anna", "insert into public.invites (email) values ('x@example.com')"), "row-level security");
  await as("owner", "insert into public.invites (email) values ('carl@example.com')");
});

test("nobody can block the owner", async () => {
  await rejects(as("anna", "insert into public.blocks (blocker_id, blocked_id) values ($1, $2)", [ids.anna, ids.owner]), "owner_protected");
});

test("members cannot change roles or disable the owner", async () => {
  await rejects(as("anna", "update public.profiles set role = 'owner' where id = $1", [ids.anna]), "immutable_field");
  await rejects(as("anna", "select public.set_member_status($1, 'disabled')", [ids.owner]), "owner_only");
  await rejects(admin("update public.profiles set status = 'disabled' where id = $1", [ids.owner]), "owner_protected");
  await rejects(admin("delete from public.profiles where id = $1", [ids.owner]), "owner_protected");
});

test("group admins cannot remove the owner; the owner can remove anyone", async () => {
  const g = (await as("anna", "select public.create_group('Familie', $1::uuid[]) as id", [[ids.owner, ids.bert]])).rows[0].id;
  await rejects(as("anna", "select public.remove_group_member($1, $2)", [g, ids.owner]), "owner_protected");
  // No delete policy: RLS silently affects zero rows.
  await as("anna", "delete from public.conversation_members where conversation_id = $1 and user_id = $2", [g, ids.owner]);
  const still = await admin("select 1 from public.conversation_members where conversation_id = $1 and user_id = $2", [g, ids.owner]);
  assert.equal(still.rows.length, 1);
  await rejects(as("anna", "select public.set_group_admin($1, $2, false)", [g, ids.owner]), "owner_protected");
  const owner = await admin("select is_admin from public.conversation_members where conversation_id = $1 and user_id = $2", [g, ids.owner]);
  assert.equal(owner.rows[0].is_admin, true);
  await as("owner", "select public.remove_group_member($1, $2)", [g, ids.anna]);
  await rejects(as("bert", "select public.remove_group_member($1, $2)", [g, ids.owner]), "admin_only");
});

test("members cannot delete owner messages; owner can delete any", async () => {
  const c = (await as("anna", "select public.start_direct($1) as id", [ids.owner])).rows[0].id;
  const m1 = (await as("owner", "insert into public.messages (conversation_id, kind, original_text, source_lang) values ($1, 'text', 'hallo', 'nl') returning id", [c])).rows[0].id;
  const m2 = (await as("anna", "insert into public.messages (conversation_id, kind, original_text, source_lang) values ($1, 'text', 'привіт', 'uk') returning id", [c])).rows[0].id;
  await rejects(as("anna", "select public.delete_message($1)", [m1]), "not_allowed");
  await as("owner", "select public.delete_message($1)", [m2]);
  const r = await admin("select deleted_at is not null as gone from public.messages where id = $1", [m2]);
  assert.equal(r.rows[0].gone, true);
});

test("a blocked member cannot post in a direct chat", async () => {
  const c = (await as("anna", "select public.start_direct($1) as id", [ids.bert])).rows[0].id;
  await as("bert", "insert into public.blocks (blocker_id, blocked_id) values ($1, $2)", [ids.bert, ids.anna]);
  await rejects(
    as("anna", "insert into public.messages (conversation_id, kind, original_text, source_lang) values ($1, 'text', 'hoi', 'nl')", [c]),
    "row-level security",
  );
  await rejects(as("anna", "select public.start_direct($1)", [ids.bert]), "blocked");
});

test("non-members cannot read a conversation", async () => {
  const c = (await as("owner", "select public.start_direct($1) as id", [ids.bert])).rows[0].id;
  const r = await as("anna", "select * from public.messages where conversation_id = $1", [c]);
  assert.equal(r.rows.length, 0);
  const conv = await as("anna", "select * from public.conversations where id = $1", [c]);
  assert.equal(conv.rows.length, 0);
});

test("disabled members lose access", async () => {
  await as("owner", "select public.set_member_status($1, 'disabled')", [ids.bert]);
  const r = await as("bert", "select * from public.conversations");
  assert.equal(r.rows.length, 0);
  await rejects(as("bert", "select public.start_direct($1)", [ids.owner]), "not_allowed");
  await as("owner", "select public.set_member_status($1, 'active')", [ids.bert]);
});

test("only the owner can delete a conversation", async () => {
  const c = (await as("anna", "select public.create_group('Test', $1::uuid[]) as id", [[ids.owner]])).rows[0].id;
  await rejects(as("anna", "select public.delete_conversation($1)", [c]), "owner_only");
  await as("owner", "select public.delete_conversation($1)", [c]);
});
