-- Kingdom In Chaos DTP v17.14: in-game player mail with transactional one-time claims.
-- Rewards are NOT written to a player wallet when the admin sends the message.
-- The wallet changes only when the recipient claims the mail through google-player.
begin;

alter table public.game_google_players
  add column if not exists last_seen_at timestamptz not null default now();

create index if not exists game_google_players_last_seen_idx
  on public.game_google_players(last_seen_at desc);

create table if not exists public.game_google_player_mail (
  mail_id uuid primary key default gen_random_uuid(),
  player_uuid uuid not null references public.game_google_players(player_uuid) on delete cascade,
  recipient_email text not null,
  subject text not null check (char_length(btrim(subject)) between 1 and 100),
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  reward_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(reward_config) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  admin_name text not null default 'Admin',
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  expires_at timestamptz,
  claimed_at timestamptz,
  claim_result jsonb,
  created_at timestamptz not null default now()
);
create index if not exists game_google_player_mail_inbox_idx
  on public.game_google_player_mail(player_uuid, created_at desc);
create index if not exists game_google_player_mail_unclaimed_idx
  on public.game_google_player_mail(player_uuid, expires_at)
  where claimed_at is null;


-- Last observed native Android wallet. Clients cannot write directly; only the
-- Google-player Edge Function (service_role) stores read-only snapshots.
create table if not exists public.game_google_player_native_wallets (
  player_uuid uuid primary key references public.game_google_players(player_uuid) on delete cascade,
  coins bigint not null default 0 check (coins >= 0),
  crystals bigint not null default 0 check (crystals >= 0),
  goblin_coins bigint not null default 0 check (goblin_coins >= 0),
  meat integer not null default 0 check (meat between 0 and 24),
  client_observed_at timestamptz not null default now(),
  server_received_at timestamptz not null default now()
);
alter table public.game_google_player_native_wallets enable row level security;
revoke all on public.game_google_player_native_wallets from public, anon, authenticated;
grant select, insert, update on public.game_google_player_native_wallets to service_role;

create table if not exists public.game_google_mail_admin_log (
  log_id bigint generated always as identity primary key,
  mail_id uuid references public.game_google_player_mail(mail_id) on delete set null,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  reason text not null check (char_length(btrim(reason)) between 4 and 500),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.game_google_player_mail enable row level security;
alter table public.game_google_mail_admin_log enable row level security;
revoke all on public.game_google_player_mail from public, anon, authenticated;
revoke all on public.game_google_mail_admin_log from public, anon, authenticated;
grant select, insert, update, delete on public.game_google_player_mail to service_role;
grant select, insert, update, delete on public.game_google_mail_admin_log to service_role;
grant usage, select on sequence public.game_google_mail_admin_log_log_id_seq to service_role;

create or replace function public.game_google_claim_player_mail(
  p_google_sub text,
  p_mail_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_mail public.game_google_player_mail;
  v_wallet public.game_google_player_economy;
  v_cfg public.game_meat_config;
  v_reward jsonb;
  v_coins bigint;
  v_crystals bigint;
  v_goblin bigint;
  v_meat integer;
begin
  if p_google_sub is null or btrim(p_google_sub) = '' or p_mail_id is null then
    raise exception 'Data surat tidak valid.';
  end if;
  select * into v_player
    from public.game_google_players
   where google_sub = p_google_sub;
  if not found then raise exception 'Pemain Google tidak ditemukan.'; end if;

  select * into v_mail
    from public.game_google_player_mail
   where mail_id = p_mail_id and player_uuid = v_player.player_uuid
   for update;
  if not found then raise exception 'Surat tidak ditemukan untuk akun ini.'; end if;
  if v_mail.claimed_at is not null then raise exception 'Hadiah surat ini sudah pernah diklaim.'; end if;
  if v_mail.expires_at is not null and now() > v_mail.expires_at then
    raise exception 'Surat sudah kedaluwarsa.';
  end if;

  v_reward := coalesce(v_mail.reward_config, '{}'::jsonb);
  v_coins := coalesce((v_reward->>'coins')::bigint, 0);
  v_crystals := coalesce((v_reward->>'crystals')::bigint, 0);
  v_goblin := coalesce((v_reward->>'goblin_coins')::bigint, 0);
  v_meat := coalesce((v_reward->>'meat')::integer, 0);
  if v_coins < 0 or v_crystals < 0 or v_goblin < 0 or v_meat < 0 then
    raise exception 'Isi hadiah surat tidak valid.';
  end if;
  if v_coins > 2147483647 or v_crystals > 2147483647 or v_goblin > 2147483647 or v_meat > 24 then
    raise exception 'Hadiah surat melebihi batas yang diizinkan.';
  end if;

  insert into public.game_google_player_economy(player_uuid)
    values (v_player.player_uuid) on conflict (player_uuid) do nothing;
  perform public.game_google_regenerate_meat(v_player.player_uuid);
  select * into v_cfg from public.game_meat_config where id = true;
  select * into v_wallet
    from public.game_google_player_economy
   where player_uuid = v_player.player_uuid
   for update;

  if v_wallet.coins + v_coins > 2147483647
     or v_wallet.crystals + v_crystals > 2147483647
     or v_wallet.goblin_coins + v_goblin > 2147483647 then
    raise exception 'Saldo setelah klaim akan melewati batas wallet game.';
  end if;

  update public.game_google_player_economy
     set coins = coins + v_coins,
         crystals = crystals + v_crystals,
         goblin_coins = goblin_coins + v_goblin,
         meat = least(coalesce(v_cfg.capacity, 24), meat + v_meat),
         updated_at = now()
   where player_uuid = v_player.player_uuid;

  update public.game_google_player_mail
     set claimed_at = now(), claim_result = v_reward
   where mail_id = v_mail.mail_id and claimed_at is null
   returning * into v_mail;
  if not found then raise exception 'Surat sudah diklaim pada perangkat lain.'; end if;

  update public.game_google_players set last_seen_at = now(), updated_at = now()
   where player_uuid = v_player.player_uuid;

  return jsonb_build_object(
    'mail', to_jsonb(v_mail),
    'state', public.game_google_player_state(p_google_sub)
  );
end;
$$;
revoke all on function public.game_google_claim_player_mail(text, uuid) from public, anon, authenticated;
grant execute on function public.game_google_claim_player_mail(text, uuid) to service_role;

commit;
