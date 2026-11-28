from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def test_bakat_button_is_not_hijacked():
    overlay = read("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "return 1;" not in overlay
    assert "0.352f" not in overlay
    assert "return 0;" in overlay and "return 2;" in overlay


def test_admin_has_separate_pages_and_player_table():
    html = read("admin.html")
    for page in ["maintenance", "pemain", "kode", "surat", "aktivitas", "boss", "event"]:
        assert 'id="page-%s"' % page in html
        assert 'data-go="%s"' % page in html
    assert "<th>Nama</th><th>ID</th><th>Koin</th><th>DM</th>" in html
    assert 'id="playerSearch"' in html


def test_game_admin_provisions_service_admin():
    ts = read("supabase/functions/game-admin/index.ts")
    assert "provisionServiceAdmin" in ts
    assert 'role: "super_admin"' in ts
    assert ts == read("kingdom-in-chaos-dtp-game-admin-function-v17_14_18.ts")
    assert read("admin.html") == read("kingdom-in-chaos-dtp-admin-v17_14_18.html")
