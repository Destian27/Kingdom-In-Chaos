-- v17.14.1: unified activity trail for Google players and dashboard admins.
begin;

create table if not exists public.game_google_activity (
  activity_id bigint generated always as identity primary key,
  actor_type text not null check (actor_type in ('player','admin')),
  player_uuid uuid references public.game_google_players(player_uuid) on delete set null,
  admin_user_id uuid references auth.users(id) on delete set null,
  actor_email text not null default '',
  action text not null check (char_length(btrim(action)) between 1 and 80),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  constraint game_google_activity_actor_check check (
    (actor_type = 'player' and player_uuid is not null) or
    (actor_type = 'admin' and admin_user_id is not null)
  )
);
create index if not exists game_google_activity_created_idx
  on public.game_google_activity(created_at desc);
create index if not exists game_google_activity_player_idx
  on public.game_google_activity(player_uuid, created_at desc);

alter table public.game_google_activity enable row level security;
revoke all on public.game_google_activity from public, anon, authenticated;
grant select, insert on public.game_google_activity to service_role;
grant usage, select on sequence public.game_google_activity_activity_id_seq to service_role;

commit;
