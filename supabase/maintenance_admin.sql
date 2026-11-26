-- Jalankan sekali di Supabase SQL Editor (proyek gunzwimrxspbmiducphg).
-- Aman dijalankan ulang. Menulis ke app_maintenance hanya lewat Edge Function.

create table if not exists public.app_maintenance (
  id integer primary key default 1,
  is_active boolean not null default false,
  title text not null default 'SEDANG MAINTENANCE',
  message text not null default 'Game sedang dalam perbaikan. Silakan kembali beberapa saat lagi.',
  start_at timestamptz,
  end_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint app_maintenance_single_row check (id = 1)
);
insert into public.app_maintenance (id) values (1) on conflict (id) do nothing;

alter table public.app_maintenance enable row level security;
drop policy if exists app_maintenance_read on public.app_maintenance;
create policy app_maintenance_read on public.app_maintenance
  for select to anon, authenticated using (true);
-- Tidak ada policy insert/update/delete: anon tidak bisa mengubah data.
revoke insert, update, delete on public.app_maintenance from anon, authenticated;

create or replace function public.touch_app_maintenance()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists app_maintenance_touch on public.app_maintenance;
create trigger app_maintenance_touch before update on public.app_maintenance
  for each row execute function public.touch_app_maintenance();

-- Riwayat perubahan dari admin (hanya service role yang bisa baca/tulis).
create table if not exists public.app_maintenance_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  is_active boolean,
  title text,
  message text,
  end_at timestamptz
);
alter table public.app_maintenance_log enable row level security;

-- Realtime: game dapat dorongan instan tiap tabel berubah.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'app_maintenance'
  ) then
    alter publication supabase_realtime add table public.app_maintenance;
  end if;
end $$;
alter table public.app_maintenance replica identity full;
