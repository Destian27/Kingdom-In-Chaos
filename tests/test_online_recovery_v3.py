from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_v3_migration_adds_save_history_and_match_state():
    sql = (ROOT / "supabase/migrations/202611260002_online_recovery_v3.sql").read_text()
    assert "game_player_save_history" in sql
    assert "game_archive_player_save_before_update" in sql
    assert "get_my_pvp_match_state" in sql
    assert "status = 'in_progress'" in sql


def test_competitive_review_is_server_only_and_audited():
    sql = (ROOT / "supabase/migrations/202611260002_online_recovery_v3.sql").read_text()
    assert "game_online_review_audit" in sql
    assert "admin_review_pvp_result" in sql
    assert "admin_review_world_boss_claim" in sql
    assert "to service_role" in sql
    assert "from public, anon, authenticated" in sql


def test_review_gateway_requires_confirmation_and_limits_payload():
    ts = (ROOT / "supabase/functions/game-online/index.ts").read_text()
    assert "MAX_BODY_BYTES" in ts
    assert "confirmed_by_human !== true" in ts
    assert "x-kic-review-key" in ts
    assert "result.error.message" not in ts
    assert "KIC_REVIEW_ALLOWED_ORIGINS" in ts




def test_docs_do_not_claim_complete_native_restoration():
    doc = (ROOT / "supabase/ONLINE-RECOVERY-V3.md").read_text()
    assert "tidak menjalankan simulasi pertarungan native" in doc
    assert "APK final belum dibuat/diuji" in doc
