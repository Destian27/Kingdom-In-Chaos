from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "admin.html").read_text()
TS = (ROOT / "supabase/functions/game-admin/index.ts").read_text()
SQL = (ROOT / "supabase/migrations/202611260003_admin_player_management.sql").read_text()


def test_admin_html_has_read_only_google_dashboard_and_reward_tools():
    for token in [
        "Manajemen Data Pemain", "game-admin", "googlePlayerRows",
        "rewardCodesAdminCard", "playerMailAdminCard", "googleActivityAdminCard",
        "Kirim Surat ke Kotak Surat Pemain", "google-admin-dashboard",
    ]:
        assert token in HTML
    for forbidden in ["ecoCoins", "ecoCrystals", "btnSaveProfile", "btnSaveEconomy", "btnSaveCloud", "userDetailCard"]:
        assert forbidden not in HTML


def test_admin_browser_does_not_embed_service_role_secret():
    assert "SUPABASE_SERVICE_ROLE_KEY" not in HTML
    assert "service_role" not in HTML.lower()
    assert 'id="gameAdminLoginCard"' not in HTML
    assert 'admin_credentials: { name: creds.name, password: creds.password }' in HTML
    assert 'id="playerMailAdminCard"' in HTML
    assert 'send_player_mail' in HTML
    assert 'google-admin-dashboard' in HTML


def test_edge_function_requires_authenticated_admin():
    assert "auth.getUser(token)" in TS
    assert "MAINTENANCE_ADMIN_NAME" in TS
    assert "MAINTENANCE_ADMIN_PASSWORD" in TS
    assert "verifyMaintenanceCredentials(body.admin_credentials)" in TS
    assert 'from("game_admin_users")' in TS
    assert '.eq("active", true)' in TS
    assert 'status: 403' in TS


def test_edge_function_has_no_direct_player_edit_or_wallet_routes():
    assert 'action === "update_economy"' not in TS
    assert 'action === "update_profile"' not in TS
    assert 'action === "update_save"' not in TS
    assert 'action === "list_google_players"' in TS
    assert 'action === "send_player_mail"' in TS
    assert 'game_google_player_mail' in TS


def test_admin_tables_are_private_and_not_granted_to_clients():
    for table in ["game_admin_users", "game_admin_player_economy", "game_admin_audit"]:
        assert f"alter table public.{table} enable row level security" in SQL
        assert f"revoke all on public.{table} from public, anon, authenticated" in SQL
    assert "YOUR_ADMIN_EMAIL" in SQL
    assert "game_admin_init_player_economy" in SQL
