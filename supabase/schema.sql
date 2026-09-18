-- Run once in the Supabase SQL editor. Each user can only access their own
-- device snapshots and attachment objects.
create table if not exists public.device_snapshots (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.device_snapshots enable row level security;
create policy "snapshot owner read" on public.device_snapshots
  for select using (auth.uid() = user_id);
create policy "snapshot owner insert" on public.device_snapshots
  for insert with check (auth.uid() = user_id);
create policy "snapshot owner update" on public.device_snapshots
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "snapshot owner delete" on public.device_snapshots
  for delete using (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

create policy "attachment owner read" on storage.objects
  for select using (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "attachment owner insert" on storage.objects
  for insert with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "attachment owner update" on storage.objects
  for update using (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "attachment owner delete" on storage.objects
  for delete using (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);
