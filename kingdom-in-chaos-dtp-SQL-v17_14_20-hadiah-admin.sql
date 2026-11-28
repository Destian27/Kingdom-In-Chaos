-- =====================================================================
-- v17.14.20: HADIAH ADMIN MASUK OTOMATIS
--   * Surat admin sekarang bisa membawa Mata Event (event_eyes); sebelumnya diabaikan diam-diam.
--   * Surat dengan hadiah diklaim OTOMATIS oleh Edge Function google-player (aksi pull_rewards),
--     karena layar Surat di game sudah dihapus sejak v17.14.19. Fungsi klaim di bawah dipakai ulang.
--   * Tidak ada tabel baru. Aman dijalankan ulang. Jalankan SETELAH SQL v17.14.19.
-- =====================================================================
begin;

alter table public.game_google_player_economy
  add column if not exists event_eyes bigint not null default 0 check (event_eyes >= 0);

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
  v_eyes bigint;
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
  v_eyes := coalesce((v_reward->>'event_eyes')::bigint, 0);
  if v_coins < 0 or v_crystals < 0 or v_goblin < 0 or v_meat < 0 or v_eyes < 0 then
    raise exception 'Isi hadiah surat tidak valid.';
  end if;
  if v_coins > 2147483647 or v_crystals > 2147483647 or v_goblin > 2147483647 or v_eyes > 2147483647 or v_meat > 24 then
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
     or v_wallet.goblin_coins + v_goblin > 2147483647
     or v_wallet.event_eyes + v_eyes > 2147483647 then
    raise exception 'Saldo setelah klaim akan melewati batas wallet game.';
  end if;

  update public.game_google_player_economy
     set coins = coins + v_coins,
         crystals = crystals + v_crystals,
         goblin_coins = goblin_coins + v_goblin,
         event_eyes = event_eyes + v_eyes,
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
