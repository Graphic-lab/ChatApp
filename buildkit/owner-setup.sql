-- Run ONCE in Supabase → SQL Editor, after the migrations.
-- Replace the placeholders. Never commit real e-mail addresses (public repo).

insert into public.app_config (owner_email)
values (lower('OWNER@EXAMPLE.COM'))
on conflict (id) do update set owner_email = excluded.owner_email;

-- Optional: first invites (the owner can add more in the app: Instellingen → Beheer).
insert into public.invites (email)
values (lower('PARTNER@EXAMPLE.COM'))
on conflict do nothing;
