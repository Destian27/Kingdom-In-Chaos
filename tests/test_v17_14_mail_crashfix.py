from pathlib import Path
import re
import hashlib

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def test_lifemax_patch_is_exact_idempotent_and_applies_to_both_arm_abis():
    src = read('tools/patch_lifemax_crash.py')
    assert 'OFFSET = 0x305330' in src
    assert '30 b5 85 b0' in src
    assert '18 20 70 47' in src
    assert '"armeabi", "armeabi-v7a"' in src
    for abi in ('armeabi', 'armeabi-v7a'):
        lib = ROOT / 'kingdom-in-chaos-decompiled' / 'lib' / abi / 'libgame.so'
        raw = lib.read_bytes()
        assert raw[0x305330:0x305334] == bytes.fromhex('18 20 70 47')


def test_crash_reported_lifemax_is_guarded_in_apk_build_pipeline():
    build = read('build_dtp.py')
    assert 'patch_lifemax_crash()' in build
    assert 'patch_lifemax_crash.py' in build
    assert build.index('patch_native_barter()') < build.index('patch_lifemax_crash()') < build.index('compile_native_bridge()')


def test_player_mail_is_private_and_claim_rpc_is_single_use_transactional():
    sql = read('supabase/migrations/202611270002_player_mail_realtime.sql')
    assert 'create table if not exists public.game_google_player_mail' in sql
    assert 'alter table public.game_google_player_mail enable row level security' in sql
    assert 'revoke all on public.game_google_player_mail from public, anon, authenticated' in sql
    assert 'where mail_id = p_mail_id and player_uuid = v_player.player_uuid' in sql
    assert 'for update' in sql
    assert 'if v_mail.claimed_at is not null then raise exception' in sql
    assert 'set claimed_at = now(), claim_result = v_reward' in sql
    assert 'grant execute on function public.game_google_claim_player_mail(text, uuid) to service_role' in sql


def test_mail_is_delivered_to_game_inbox_and_not_by_email():
    admin = read('supabase/functions/game-admin/index.ts')
    player = read('supabase/functions/google-player/index.ts')
    html = read('admin.html')
    java = read('dtp/src/com/destian/dtp/GameMailActivity.java')
    assert 'send_player_mail' in admin and 'game_google_player_mail' in admin
    assert 'wallet_credited: false' in admin
    assert 'action === "get_mail"' in player and 'action === "claim_mail"' in player
    assert 'recipient_email' in html and 'Kirim Surat ke Kotak Surat Pemain' in html
    assert 'Email Google hanya dipakai untuk menemukan pemain tujuan' in html
    assert 'Klaim Hadiah' in java and 'backend.claimMail' in java
    assert 'GameMailActivity' in read('kingdom-in-chaos-decompiled/AndroidManifest.xml')
    assert 'addMailEntry(activity, root)' in read('dtp/src/com/destian/dtp/GameOnlineOverlay.java')


def test_admin_no_longer_has_second_supabase_login_or_direct_wallet_action():
    html = read('admin.html')
    admin = read('supabase/functions/game-admin/index.ts')
    assert 'id="gameAdminLoginCard"' not in html
    assert 'id="gameAdminEmail"' not in html
    assert 'id="gameAdminPassword"' not in html
    assert 'admin_credentials: { name: creds.name, password: creds.password }' in html
    assert 'action === "update_economy"' not in admin
    assert 'send_player_mail' in admin


def test_admin_realtime_broadcast_plus_poll_fallback_refreshes_player_and_mail_tables():
    html = read('admin.html')
    edge = read('supabase/functions/google-player/index.ts')
    admin = read('supabase/functions/game-admin/index.ts')
    assert 'google-admin-dashboard' in html
    assert 'google_player_changed' in html
    assert '}, 15000)' in html
    assert 'notifyGoogleAdminDashboard(identity, action)' in edge
    assert 'publishRealtimeBroadcast("google-admin-dashboard", "google_player_changed"' in admin
    assert 'last_seen_at' in admin


def test_version_and_package_are_bumped_for_v17_14_2():
    yml = read('kingdom-in-chaos-decompiled/apktool.yml')
    build = read('build_dtp.py')
    assert 'versionCode: 12' in yml
    assert 'versionName: 17.14.2' in yml
    assert 'KingdomInChaosDTP-v17.14.2-google-mail-crashfix.apk' in build


def test_claimed_mail_rewards_are_journaled_and_applied_to_native_wallet_and_life():
    sync = read('dtp/src/com/destian/dtp/NativeGameRuntimeSync.java')
    bridge = read('dtp/src/com/destian/dtp/NativeGameRuntimeBridge.java')
    native = read('dtp/native/game_runtime_bridge.cpp')
    app = read('dtp/src/com/destian/dtp/DtpApp.java')
    mail = read('dtp/src/com/destian/dtp/GameMailActivity.java')
    assert 'queueClaimedMail' in sync
    assert 'MAIL_PENDING_PREFIX' in sync and 'MAIL_APPLIED_PREFIX' in sync
    assert 'Persist the exact target before touching libgame.so' in sync
    assert 'gl.queueEvent' in sync
    assert 'applyMailWalletTargets' in bridge
    assert 'applyWalletTargetsNative' in native
    assert '_Z12IncreaseLifeib' in native
    assert '_Z7LifeMaxv' in native
    assert 'balanceLife(&beforeLife, &secondsToNextLife)' in native
    assert 'NativeGameRuntimeSync.reconcileClaimedMail(a)' in app
    assert 'NativeGameRuntimeSync.queueClaimedMail' in mail


def test_native_lifemax_guard_still_returns_24_for_achievement_reward_flow():
    patch = read('tools/patch_lifemax_crash.py')
    assert 'movs r0,#24; bx lr' in patch
    native = read('dtp/native/game_runtime_bridge.cpp')
    assert 'const int lifeMax = getLifeMax();' in native
    assert 'const int afterLifeMax = getLifeMax();' in native
    # The second BalanceLifeStatus out parameter is regen time, not maximum life.
    assert 'balanceLife(&beforeLife, &secondsToNextLife)' in native
    assert 'balanceLife(&life, &secondsToNextLife)' in native


def test_admin_reads_native_wallet_snapshot_from_google_players_without_edit_endpoint():
    sql = read('supabase/migrations/202611270002_player_mail_realtime.sql')
    player = read('supabase/functions/google-player/index.ts')
    admin = read('supabase/functions/game-admin/index.ts')
    html = read('admin.html')
    app = read('dtp/src/com/destian/dtp/DtpApp.java')
    sync = read('dtp/src/com/destian/dtp/NativeGameRuntimeSync.java')
    assert 'game_google_player_native_wallets' in sql
    assert 'revoke all on public.game_google_player_native_wallets from public, anon, authenticated' in sql
    assert 'async function syncNativeWallet' in player
    assert 'action === "sync_native_wallet"' in player
    assert 'game_google_player_native_wallets' in admin
    assert 'native_wallet: nativeWalletMap.get(p.player_uuid)' in admin
    assert 'const useNative = !!p.native_wallet && nativeAt >= cloudAt;' in html
    assert 'const e = useNative ? p.native_wallet : (p.economy || p.native_wallet || {});' in html
    assert '10000L' in app
    assert 'NativeGameRuntimeSync.syncGoogleWallet(active)' in app
    assert 'backend.syncNativeWallet' in sync
