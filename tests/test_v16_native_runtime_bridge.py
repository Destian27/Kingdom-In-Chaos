from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def test_admin_currency_changes_have_individual_revisions():
    sql = read("supabase/kingdom-in-chaos-dtp-SQL-GABUNGAN-v17.3-ALL-IN-ONE.sql")
    assert "coins_admin_revision" in sql
    assert "crystals_admin_revision" in sql
    assert "goblin_coins_admin_revision" in sql
    assert "case when p_fields ? 'coins' then now() else coins_admin_revision end" in sql
    assert "case when p_fields ? 'crystals' then now() else crystals_admin_revision end" in sql
    assert "case when p_fields ? 'goblin_coins' then now() else goblin_coins_admin_revision end" in sql
    assert "native game 32-bit wallet limit" in sql

def test_android_only_pushes_admin_revised_currency_to_native_wallet():
    sync = read("dtp/src/com/destian/dtp/NativeGameRuntimeSync.java")
    bridge = read("dtp/native/game_runtime_bridge.cpp")
    assert "coins_admin_revision" in sync and "crystals_admin_revision" in sync
    assert "goblin_coins_admin_revision" in sync
    assert "native_coins_revision_applied_" in sync
    assert "NativeGameRuntimeBridge.applyEconomy(coins, crystals, goblin, eventEyes)" in sync
    assert "targetCoins < -1" in bridge and "targetCrystals < -1" in bridge
    assert "targetGoblinCoins < -1" in bridge
    assert "_ZN12LevelManager7getCoinEv" in bridge
    assert "_ZN12LevelManager10getCrystalEv" in bridge
    assert "_ZN12LevelManager13getGoblinCoinEv" in bridge

def test_cave_boss_is_fetched_in_game_but_banner_limit_is_explicit():
    app = read("dtp/src/com/destian/dtp/DtpApp.java")
    backend = read("dtp/src/com/destian/dtp/SupabaseGameBackend.java")
    overlay = read("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "getActiveCaveBoss()" in app and "h.postDelayed(this, 15000L)" in app
    assert '"/rest/v1/rpc/get_active_cave_boss"' in backend
    assert "does not create an enemy" in overlay

def test_build_workflow_installs_ndk_for_jni_bridge():
    script = read("build_dtp.py")
    workflow = read(".github/workflows/build-apk.yml")
    assert "compile_native_bridge()" in script
    assert "ANDROID_NDK_HOME" in script
    assert 'ndk;27.2.12479018' in workflow


def test_v17_native_event_eyes_uses_original_festival_key():
    root = Path(__file__).resolve().parents[1]
    cpp = (root / "dtp/native/game_runtime_bridge.cpp").read_text()
    java = (root / "dtp/src/com/destian/dtp/NativeGameRuntimeSync.java").read_text()
    assert "_ZN15UserDataManager13getGlobalInfoE12UserDataType" in cpp
    assert "_ZN15UserDataManager13setGlobalInfoE12UserDataTypei" in cpp
    assert "getGlobalInfo(userDataManager, 0x85)" in cpp
    assert "setGlobalInfo(userDataManager, 0x85, wantedEventEyes)" in cpp
    assert '"event_eyes_admin_revision"' in java
    assert "native_event_eyes_revision_applied_" in java



def test_v17_event_store_admin_and_wib_schedule_are_present():
    sql = read("supabase/migrations/202611260006_event_store_v17.sql")
    admin = read("admin.html")
    edge = read("supabase/functions/game-admin/index.ts")
    assert "create table if not exists public.game_event_store_config" in sql
    assert "create table if not exists public.game_event_store_items" in sql
    assert "create or replace function public.admin_save_event_store" in sql
    assert "create or replace function public.get_active_event_store" in sql
    assert "'Asia/Jakarta'" in sql
    assert "v_cfg.recurrence = 'daily'" in sql and "'weekly'" in sql
    assert "refresh_at" in sql
    assert 'id="btnSaveEventEyes"' in admin and 'id="caveBossAdminCard"' in admin
    assert '"get_event_store_admin"' in edge and '"save_event_store"' in edge


def test_v17_event_eyes_database_value_is_limited_to_native_int32():
    sql = read("supabase/migrations/202611260006_event_store_v17.sql")
    html = read("admin.html")
    assert "event_eyes between 0 and 2147483647" in sql
    assert "Number(value) > 2147483647" in html
    assert "create or replace function public.get_my_game_runtime_state()" in sql
    assert "event_eyes_admin_revision" in sql
