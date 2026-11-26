from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "admin.html").read_text()
TS = (ROOT / "supabase/functions/game-admin/index.ts").read_text()
SQL = (ROOT / "supabase/migrations/202611260003_admin_player_management.sql").read_text()


def test_admin_html_has_player_management_and_currency_fields():
    for token in [
        "Manajemen Data Pemain", "game-admin", "ecoCoins", "ecoCrystals",
        "ecoGoblin", "ecoHeroXp", "ecoPlayerXp", "ecoExtra", "saveJson",
        "btnSaveProfile", "btnSaveEconomy", "btnSaveCloud",
    ]:
        assert token in HTML


def test_admin_browser_does_not_embed_service_role_secret():
    assert "SUPABASE_SERVICE_ROLE_KEY" not in HTML
    assert "service_role" not in HTML.lower()
    assert "auth/v1/token?grant_type=password" in HTML


def test_edge_function_requires_authenticated_admin():
    assert "auth.getUser(token)" in TS
    assert 'from("game_admin_users")' in TS
    assert '.eq("active", true)' in TS
    assert 'status: 403' in TS


def test_edge_function_whitelists_economy_fields_and_audits_changes():
    for field in ["coins", "crystals", "goblin_coins", "hero_xp", "hero_level", "player_xp", "player_level", "energy", "stamina", "honor_points", "arena_tokens", "skill_points", "extra_stats"]:
        assert field in TS
    # Economy write and audit are committed atomically by a database RPC.
    assert 'service.rpc("admin_update_player_economy"' in TS
    assert 'await audit(adminId, targetId, "profile_update"' in TS
    assert 'await audit(adminId, targetId, "save_update"' in TS


def test_admin_tables_are_private_and_not_granted_to_clients():
    for table in ["game_admin_users", "game_admin_player_economy", "game_admin_audit"]:
        assert f"alter table public.{table} enable row level security" in SQL
        assert f"revoke all on public.{table} from public, anon, authenticated" in SQL
    assert "YOUR_ADMIN_EMAIL" in SQL
    assert "game_admin_init_player_economy" in SQL
