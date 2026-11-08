-- Heart to Heart: core schema, owner protection and access rules.
-- All guarantees in this file are enforced by Postgres (RLS, triggers, RPC),
-- not by the app. The iOS client is untrusted.
--
-- Owner model
--   * Exactly one profile has role 'owner'. It is assigned at signup when the
--     email matches app_config.owner_email (set once via the SQL editor).
--   * Nobody using the app can delete, disable, block, demote or remove the
--     owner from a conversation, or delete the owner's messages.
--   * The owner manages invites and can disable members and delete conversations.

-- ---------------------------------------------------------------------------
-- Configuration (no RLS policies: only the SQL editor / service role can read)
-- ---------------------------------------------------------------------------
create table public.app_config (
  id boolean primary key default true check (id),
  owner_email text not null check (owner_email = lower(owner_email))
);
alter table public.app_config enable row level security;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.invites (
  email text primary key check (email = lower(email) and position('@' in email) > 1),
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  display_name text not null default '' check (char_length(display_name) <= 60),
  language text not null default 'nl' check (char_length(language) between 2 and 10),
  speech_locale text not null default 'nl-BE' check (char_length(speech_locale) between 2 and 16),
  voice_gender text not null default 'male' check (voice_gender in ('male', 'female')),
  role text not null default 'member' check (role in ('owner', 'member')),
  status text not null default 'active' check (status in ('active', 'disabled')),
  created_at timestamptz not null default now()
);
create unique index profiles_single_owner on public.profiles ((true)) where role = 'owner';

create table public.contacts (
  user_id uuid not null references public.profiles (id) on delete cascade,
  contact_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, contact_id),
  check (user_id <> contact_id)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct', 'group')),
  title text check (title is null or char_length(title) <= 80),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  is_admin boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('voice', 'text')),
  original_text text not null check (char_length(original_text) <= 4000),
  source_lang text not null check (char_length(source_lang) between 2 and 10),
  audio_path text,
  duration_ms integer check (duration_ms is null or duration_ms between 0 and 600000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index messages_conversation_created_idx on public.messages (conversation_id, created_at);

-- ---------------------------------------------------------------------------
-- Helper functions (security definer so policies can use them without recursion)
-- ---------------------------------------------------------------------------
create function public.owner_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.profiles where role = 'owner' limit 1;
$$;

create function public.is_owner(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = uid and role = 'owner');
$$;

create function public.is_active_member(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = uid and status = 'active');
$$;

create function public.is_conversation_member(conv uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = uid
  );
$$;

create function public.is_conversation_admin(conv uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(uid) or exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = uid and is_admin
  );
$$;

-- True when either user has blocked the other.
create function public.is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

-- A member may post when active, in the conversation, and (for direct chats)
-- not blocked by the other participant. The owner can always post.
create function public.can_post(conv uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active_member(uid)
     and public.is_conversation_member(conv, uid)
     and (
       public.is_owner(uid)
       or not exists (
         select 1
         from public.conversations c
         join public.conversation_members m on m.conversation_id = c.id and m.user_id <> uid
         join public.blocks b on b.blocker_id = m.user_id and b.blocked_id = uid
         where c.id = conv and c.kind = 'direct'
       )
     );
$$;

-- ---------------------------------------------------------------------------
-- Signup gate and profile creation
-- ---------------------------------------------------------------------------
create function public.gate_signup() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e text := lower(coalesce(new.email, ''));
begin
  if e <> '' and (
    e = (select owner_email from public.app_config where id)
    or exists (select 1 from public.invites where email = e)
  ) then
    return new;
  end if;
  raise exception 'not_invited' using errcode = 'P0001';
end;
$$;

create trigger gate_signup
  before insert on auth.users
  for each row execute function public.gate_signup();

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e text := lower(new.email);
begin
  insert into public.profiles (id, email, display_name, role)
  values (
    new.id,
    e,
    split_part(e, '@', 1),
    case when e = (select owner_email from public.app_config where id) then 'owner' else 'member' end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Owner protection triggers
-- auth.uid() is null for the SQL editor / service role (the project owner's
-- own tooling); every app request carries a user id.
-- ---------------------------------------------------------------------------
create function public.guard_profiles() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.role = 'owner' then
      raise exception 'owner_protected' using errcode = 'P0001';
    end if;
    return old;
  end if;

  if auth.uid() is not null then
    if new.id <> old.id or new.email <> old.email or new.role <> old.role then
      raise exception 'immutable_field' using errcode = 'P0001';
    end if;
    if new.status <> old.status and not public.is_owner(auth.uid()) then
      raise exception 'owner_only' using errcode = 'P0001';
    end if;
  end if;

  if old.role = 'owner' and new.status <> 'active' then
    raise exception 'owner_protected' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger guard_profiles
  before update or delete on public.profiles
  for each row execute function public.guard_profiles();

create function public.guard_blocks() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_owner(new.blocked_id) then
    raise exception 'owner_protected' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger guard_blocks
  before insert or update on public.blocks
  for each row execute function public.guard_blocks();

create function public.guard_members() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if public.is_owner(old.user_id)
       and auth.uid() is not null
       and auth.uid() <> old.user_id
       and not public.is_owner(auth.uid()) then
      raise exception 'owner_protected' using errcode = 'P0001';
    end if;
    return old;
  end if;
  -- The owner is always admin of every conversation they are in.
  if public.is_owner(new.user_id) then
    new.is_admin := true;
  end if;
  return new;
end;
$$;

create trigger guard_members
  before insert or update or delete on public.conversation_members
  for each row execute function public.guard_members();

create function public.guard_messages() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if public.is_owner(old.sender_id) and auth.uid() is not null and not public.is_owner(auth.uid()) then
      raise exception 'owner_protected' using errcode = 'P0001';
    end if;
    return old;
  end if;
  if public.is_owner(old.sender_id) and auth.uid() is not null and not public.is_owner(auth.uid()) then
    raise exception 'owner_protected' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger guard_messages
  before update or delete on public.messages
  for each row execute function public.guard_messages();

create function public.touch_conversation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.conversations set updated_at = new.created_at where id = new.conversation_id;
  return new;
end;
$$;

create trigger touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.invites enable row level security;
alter table public.profiles enable row level security;
alter table public.contacts enable row level security;
alter table public.blocks enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

create policy invites_owner_all on public.invites
  for all to authenticated
  using (public.is_owner()) with check (public.is_owner());

create policy profiles_read on public.profiles
  for select to authenticated using (public.is_active_member());
create policy profiles_update_self_or_owner on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_owner())
  with check (id = auth.uid() or public.is_owner());

create policy contacts_own on public.contacts
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_active_member());

create policy blocks_own on public.blocks
  for all to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid() and public.is_active_member());

create policy conversations_member_read on public.conversations
  for select to authenticated using (public.is_active_member() and public.is_conversation_member(id));

create policy members_member_read on public.conversation_members
  for select to authenticated using (public.is_active_member() and public.is_conversation_member(conversation_id));

create policy messages_member_read on public.messages
  for select to authenticated using (public.is_active_member() and public.is_conversation_member(conversation_id));
create policy messages_insert on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and deleted_at is null and public.can_post(conversation_id));

-- Conversations, memberships and message deletion change only through the RPCs below.

-- ---------------------------------------------------------------------------
-- RPC
-- ---------------------------------------------------------------------------
create function public.require_active() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null or not public.is_active_member(uid) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return uid;
end;
$$;

create function public.start_direct(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
  conv uuid;
begin
  if other = me or not public.is_active_member(other) then
    raise exception 'invalid_user' using errcode = 'P0001';
  end if;
  if public.is_blocked_between(me, other) and not public.is_owner(me) then
    raise exception 'blocked' using errcode = 'P0001';
  end if;

  select c.id into conv
  from public.conversations c
  join public.conversation_members a on a.conversation_id = c.id and a.user_id = me
  join public.conversation_members b on b.conversation_id = c.id and b.user_id = other
  where c.kind = 'direct'
  limit 1;

  if conv is null then
    insert into public.conversations (kind, created_by) values ('direct', me) returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, me), (conv, other);
  end if;
  return conv;
end;
$$;

create function public.create_group(group_title text, member_ids uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
  conv uuid;
begin
  if coalesce(trim(group_title), '') = '' then
    raise exception 'title_required' using errcode = 'P0001';
  end if;
  insert into public.conversations (kind, title, created_by)
  values ('group', trim(group_title), me) returning id into conv;

  insert into public.conversation_members (conversation_id, user_id, is_admin) values (conv, me, true);
  insert into public.conversation_members (conversation_id, user_id)
  select conv, p.id
  from public.profiles p
  where p.id = any (member_ids)
    and p.id <> me
    and p.status = 'active'
    and (public.is_owner(me) or not public.is_blocked_between(me, p.id))
  on conflict do nothing;
  return conv;
end;
$$;

create function public.add_group_member(conv uuid, member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
begin
  if not exists (select 1 from public.conversations where id = conv and kind = 'group') then
    raise exception 'not_a_group' using errcode = 'P0001';
  end if;
  if not public.is_conversation_admin(conv, me) then
    raise exception 'admin_only' using errcode = 'P0001';
  end if;
  if not public.is_active_member(member) then
    raise exception 'invalid_user' using errcode = 'P0001';
  end if;
  if public.is_blocked_between(me, member) and not public.is_owner(me) then
    raise exception 'blocked' using errcode = 'P0001';
  end if;
  insert into public.conversation_members (conversation_id, user_id)
  values (conv, member) on conflict do nothing;
end;
$$;

-- Remove a member, or leave when member = caller.
create function public.remove_group_member(conv uuid, member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
begin
  if not exists (select 1 from public.conversations where id = conv and kind = 'group') then
    raise exception 'not_a_group' using errcode = 'P0001';
  end if;
  if member <> me and not public.is_conversation_admin(conv, me) then
    raise exception 'admin_only' using errcode = 'P0001';
  end if;
  if public.is_owner(member) and member <> me then
    raise exception 'owner_protected' using errcode = 'P0001';
  end if;
  delete from public.conversation_members where conversation_id = conv and user_id = member;
end;
$$;

create function public.set_group_admin(conv uuid, member uuid, make_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
begin
  if not public.is_conversation_admin(conv, me) then
    raise exception 'admin_only' using errcode = 'P0001';
  end if;
  if public.is_owner(member) and not make_admin then
    raise exception 'owner_protected' using errcode = 'P0001';
  end if;
  update public.conversation_members set is_admin = make_admin
  where conversation_id = conv and user_id = member;
end;
$$;

create function public.rename_group(conv uuid, group_title text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
begin
  if not public.is_conversation_admin(conv, me) then
    raise exception 'admin_only' using errcode = 'P0001';
  end if;
  if coalesce(trim(group_title), '') = '' then
    raise exception 'title_required' using errcode = 'P0001';
  end if;
  update public.conversations set title = trim(group_title) where id = conv and kind = 'group';
end;
$$;

-- Owner only: delete a conversation with all its messages.
create function public.delete_conversation(conv uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
begin
  if not public.is_owner(me) then
    raise exception 'owner_only' using errcode = 'P0001';
  end if;
  delete from public.conversations where id = conv;
end;
$$;

-- Soft delete: the sender or the owner. Owner messages can only be deleted by the owner.
create function public.delete_message(message uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
  msg public.messages;
begin
  select * into msg from public.messages where id = message;
  if msg.id is null or not public.is_conversation_member(msg.conversation_id, me) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if msg.sender_id <> me and not public.is_owner(me) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  update public.messages
  set deleted_at = now(), original_text = '', audio_path = null
  where id = message;
end;
$$;

-- Owner only: enable or disable a member account.
create function public.set_member_status(member uuid, new_status text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
begin
  if not public.is_owner(me) then
    raise exception 'owner_only' using errcode = 'P0001';
  end if;
  update public.profiles set status = new_status where id = member;
end;
$$;

-- Add a contact by email (must be an existing, active member).
create function public.add_contact_by_email(contact_email text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.require_active();
  other uuid;
begin
  select id into other from public.profiles
  where email = lower(trim(contact_email)) and status = 'active';
  if other is null or other = me then
    raise exception 'user_not_found' using errcode = 'P0001';
  end if;
  insert into public.contacts (user_id, contact_id) values (me, other) on conflict do nothing;
  return other;
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges: helpers and RPCs only for signed-in users.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
grant execute on function
  public.owner_id(),
  public.is_owner(uuid),
  public.is_active_member(uuid),
  public.is_conversation_member(uuid, uuid),
  public.is_conversation_admin(uuid, uuid),
  public.is_blocked_between(uuid, uuid),
  public.can_post(uuid, uuid),
  public.require_active(),
  public.start_direct(uuid),
  public.create_group(text, uuid[]),
  public.add_group_member(uuid, uuid),
  public.remove_group_member(uuid, uuid),
  public.set_group_admin(uuid, uuid, boolean),
  public.rename_group(uuid, text),
  public.delete_conversation(uuid),
  public.delete_message(uuid),
  public.set_member_status(uuid, text),
  public.add_contact_by_email(text)
to authenticated;
