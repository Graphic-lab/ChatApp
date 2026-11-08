-- Supabase platform pieces: private voice bucket and realtime publication.
-- Voice clips live at voice/<conversation_id>/<message_id>.m4a

insert into storage.buckets (id, name, public)
values ('voice', 'voice', false)
on conflict (id) do nothing;

create policy voice_member_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'voice'
    and public.is_active_member()
    and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
  );

create policy voice_member_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'voice'
    and public.can_post(((storage.foldername(name))[1])::uuid)
  );

-- No update/delete policies: clips are immutable for app users.

alter publication supabase_realtime add table public.messages, public.conversation_members, public.conversations;
