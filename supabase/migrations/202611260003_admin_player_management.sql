-- Kingdom in Chaos DTP: secure player administration (v11)
-- Apply AFTER the v10 online backend migrations.
-- This migration creates server-only admin/economy/audit tables. The browser/APK
-- must call the game-admin Edge Function; never expose SUPABASE_SERVICE_ROLE_KEY.
begin;

create table if not exists public.game_admin_users (
    user_id uuid primary key references auth.users(id) on delete cascade,
    role text not null default 'admin' check (role in ('admin', 'super_admin')),
    active boolean not null default true,
    created_at timestamptz not null default now(),
    created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.game_admin_player_economy (
    user_id uuid primary key references auth.users(id) on delete cascade,
    coins bigint not null default 0 check (coins >= 0),
    crystals bigint not null default 0 check (crystals >= 0),
    goblin_coins bigint not null default 0 check (goblin_coins >= 0),
    hero_xp bigint not null default 0 check (hero_xp >= 0),
    hero_level integer not null default 1 check (hero_level between 1 and 1000000),
    player_xp bigint not null default 0 check (player_xp >= 0),
    player_level integer not null default 1 check (player_level between 1 and 1000000),
    energy bigint not null default 0 check (energy >= 0),
    stamina bigint not null default 0 check (stamina >= 0),
    honor_points bigint not null default 0 check (honor_points >= 0),
    arena_tokens bigint not null default 0 check (arena_tokens >= 0),
    skill_points bigint not null default 0 check (skill_points >= 0),
    extra_stats jsonb not null default '{}'::jsonb check (jsonb_typeof(extra_stats) = 'object'),
    updated_at timestamptz not null default now(),
    updated_by uuid references auth.users(id) on delete set null
);

create table if not exists public.game_admin_audit (
    audit_id bigint generated always as identity primary key,
    admin_user_id uuid references auth.users(id) on delete set null,
    target_user_id uuid references auth.users(id) on delete set null,
    action text not null check (action in ('economy_update', 'profile_update', 'save_update')),
    reason text not null check (char_length(btrim(reason)) between 4 and 500),
    before_data jsonb not null default '{}'::jsonb check (jsonb_typeof(before_data) = 'object'),
    after_data jsonb not null default '{}'::jsonb check (jsonb_typeof(after_data) = 'object'),
    created_at timestamptz not null default now()
);

create index if not exists game_admin_audit_target_time_idx
    on public.game_admin_audit (target_user_id, created_at desc);
create index if not exists game_admin_audit_admin_time_idx
    on public.game_admin_audit (admin_user_id, created_at desc);

-- Keep an economy control row for existing accounts and any future Auth user.
insert into public.game_admin_player_economy (user_id)
select id from auth.users
on conflict (user_id) do nothing;

create or replace function public.game_admin_init_player_economy()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.game_admin_player_economy (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists game_admin_init_player_economy on auth.users;
create trigger game_admin_init_player_economy
after insert on auth.users
for each row execute function public.game_admin_init_player_economy();

-- Server-only data: RLS is enabled and direct grants are explicitly removed.
alter table public.game_admin_users enable row level security;
alter table public.game_admin_player_economy enable row level security;
alter table public.game_admin_audit enable row level security;
revoke all on public.game_admin_users from public, anon, authenticated;
revoke all on public.game_admin_player_economy from public, anon, authenticated;
revoke all on public.game_admin_audit from public, anon, authenticated;
grant select, insert, update, delete on public.game_admin_users to service_role;
grant select, insert, update, delete on public.game_admin_player_economy to service_role;
grant select, insert, update, delete on public.game_admin_audit to service_role;
grant usage, select on sequence public.game_admin_audit_audit_id_seq to service_role;

commit;

-- ADMIN BOOTSTRAP (run separately after the admin has an account in Supabase Auth):
-- Replace the email below with the exact email of your own admin account, then run:
-- insert into public.game_admin_users (user_id, role, active)
-- select id, 'super_admin', true from auth.users
-- where lower(email) = lower('YOUR_ADMIN_EMAIL')
-- on conflict (user_id) do update set role = 'super_admin', active = true;
-- Verify the account was added:
-- select a.user_id, u.email, a.role, a.active
-- from public.game_admin_users a join auth.users u on u.id = a.user_id;
--
-- SECURITY NOTES:
-- * Do not grant public/authenticated access to these tables.
-- * Do not include a service_role key in admin.html or any APK.
-- * Currency/XP values in this table are DTP admin-managed backend fields. They do
--   not automatically modify the original native game's local save unless the native
--   game is integrated with this table's values; see ADMIN-PLAYER-MANAGEMENT.md.
