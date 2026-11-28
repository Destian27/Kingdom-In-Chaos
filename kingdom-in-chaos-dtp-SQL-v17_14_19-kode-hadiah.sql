-- Kingdom In Chaos DTP v17.14.19 — Kode Hadiah dengan hadiah bebas (Mata Event, Kristal, Koin, Koin Goblin)
-- Aman dijalankan ulang. Jalankan SETELAH SQL GABUNGAN v17_14_17.
begin;

-- Mata Event sudah ada di wallet cloud (v17.14.17); pastikan kolomnya ada.
alter table public.game_google_player_economy
  add column if not exists event_eyes bigint not null default 0 check (event_eyes >= 0);

-- Klaim baru ditandai agar APK bisa memulihkan hadiah native yang belum masuk (tutup aplikasi di tengah jalan).
-- Klaim lama (sebelum v17.14.19) tetap false sehingga tidak dikreditkan ulang ke game.
alter table public.game_reward_code_claims
  add column if not exists native_credit boolean not null default false;
create index if not exists game_reward_claims_native_idx
  on public.game_reward_code_claims(player_uuid, claimed_at desc) where native_credit;

create or replace function public.game_google_redeem_reward_code(p_google_sub text, p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.game_google_players;
  v_code public.game_reward_codes;
  v_reward jsonb;
  v_coins bigint;
  v_crystals bigint;
  v_goblin bigint;
  v_eyes bigint;
  v_meat integer;
  v_capacity integer;
  v_wallet public.game_google_player_economy;
  v_claim_id uuid;
begin
  select * into v_player from public.game_google_players where google_sub = p_google_sub;
  if not found then raise exception 'Google player not found'; end if;
  select * into v_code from public.game_reward_codes where code = upper(btrim(p_code)) for update;
  if not found then raise exception 'Kode hadiah tidak ditemukan.'; end if;
  if not v_code.enabled then raise exception 'Kode hadiah sudah dinonaktifkan.'; end if;
  if v_code.starts_at is not null and now() < v_code.starts_at then raise exception 'Kode hadiah belum berlaku.'; end if;
  if v_code.expires_at is not null and now() > v_code.expires_at then raise exception 'Kode hadiah sudah kedaluwarsa.'; end if;
  if v_code.uses_count >= v_code.max_uses then raise exception 'Kuota kode hadiah sudah habis.'; end if;
  if exists(select 1 from public.game_reward_code_claims where code_id = v_code.code_id and player_uuid = v_player.player_uuid) then
    raise exception 'Akun ini sudah pernah memakai kode tersebut.';
  end if;

  v_reward := v_code.reward_config;
  v_coins    := coalesce((v_reward->>'coins')::bigint, 0);
  v_crystals := coalesce((v_reward->>'crystals')::bigint, 0);
  v_goblin   := coalesce((v_reward->>'goblin_coins')::bigint, 0);
  v_eyes     := coalesce((v_reward->>'event_eyes')::bigint, 0);
  v_meat     := coalesce((v_reward->>'meat')::integer, 0);
  if v_coins < 0 or v_crystals < 0 or v_goblin < 0 or v_eyes < 0 or v_meat < 0 then raise exception 'Reward tidak boleh negatif'; end if;
  if v_coins > 2147483647 or v_crystals > 2147483647 or v_goblin > 2147483647 or v_eyes > 2147483647 or v_meat > 24 then
    raise exception 'Reward melebihi batas game';
  end if;

  select capacity into v_capacity from public.game_meat_config where id = true;
  insert into public.game_google_player_economy(player_uuid) values(v_player.player_uuid) on conflict do nothing;
  select * into v_wallet from public.game_google_player_economy where player_uuid = v_player.player_uuid for update;
  if v_wallet.coins + v_coins > 2147483647 or v_wallet.crystals + v_crystals > 2147483647
     or v_wallet.goblin_coins + v_goblin > 2147483647 or v_wallet.event_eyes + v_eyes > 2147483647 then
    raise exception 'Saldo setelah klaim akan melewati batas wallet game.';
  end if;

  update public.game_google_player_economy set
    coins = coins + v_coins,
    crystals = crystals + v_crystals,
    goblin_coins = goblin_coins + v_goblin,
    event_eyes = event_eyes + v_eyes,
    meat = least(coalesce(v_capacity,24), meat + v_meat),
    updated_at = now()
  where player_uuid = v_player.player_uuid;

  insert into public.game_reward_code_claims(code_id, player_uuid, reward_applied, native_credit)
  values(v_code.code_id, v_player.player_uuid, v_reward, true)
  returning claim_id into v_claim_id;
  update public.game_reward_codes set uses_count = uses_count + 1 where code_id = v_code.code_id;

  -- state pemain (kompatibel dengan klien lama) + data klaim agar APK memasukkan hadiah ke saldo game.
  return public.game_google_player_state(p_google_sub)
    || jsonb_build_object('claim', jsonb_build_object(
         'claim_id', v_claim_id, 'code', v_code.code, 'rewards', v_reward));
end;
$$;
revoke all on function public.game_google_redeem_reward_code(text, text) from public, anon, authenticated;
grant execute on function public.game_google_redeem_reward_code(text, text) to service_role;

commit;
