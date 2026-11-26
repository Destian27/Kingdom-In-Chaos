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

create or replace function public.touch_app_maintenance()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists app_maintenance_touch on public.app_maintenance;
create trigger app_maintenance_touch
  before update on public.app_maintenance
  for each row execute function public.touch_app_maintenance();
