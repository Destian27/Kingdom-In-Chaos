"""v17.14.20: dialog Kode Hadiah asli game dikembalikan (hook native) + hadiah admin masuk otomatis."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "dtp/src/com/destian/dtp"


def read(path):
    return Path(path).read_text(encoding="utf-8")


def test_native_promo_dialog_is_hooked_and_forwarded_to_java():
    cpp = read(ROOT / "dtp/native/game_runtime_bridge.cpp")
    assert "_ZN11UIMallLayer16onInputPromoCodeEPKc" in cpp
    assert "dtpPromoCodeHook" in cpp and "onPromoCodeEntered" in cpp
    # hanya A-Z a-z 0-9 dan '-' yang diteruskan ke Java
    assert "c == '-'" in cpp
    bridge = read(SRC / "NativeGameRuntimeBridge.java")
    assert "static void onPromoCodeEntered(String code)" in bridge
    overlay = read(SRC / "GameOnlineOverlay.java")
    assert "public static void handlePromoCode" in overlay and "redeemGiftCode(code)" in overlay
    assert "queueCodeClaim" in overlay


def test_kode_hadiah_button_is_passed_through_to_original_dialog():
    overlay = read(SRC / "GameOnlineOverlay.java")
    assert "return 3;" not in overlay and "zone == 3" not in overlay
    m = re.search(r"x >= ([0-9.]+)f \* h && x <= ([0-9.]+)f \* h && y >= ([0-9.]+)f \* h && y <= ([0-9.]+)f \* h\) return -1;", overlay)
    assert m
    x0, x1, y0, y1 = map(float, m.groups())
    # tombol asli (screenshot 2340x1080): x 0.27-0.43H, y 0.93-1.0H
    assert x0 <= 0.27 and x1 >= 0.43 and y0 <= 0.93 and y1 >= 0.99
    # dicek sebelum kotak avatar yang bertumpuk dengannya
    assert overlay.index("return -1;") < overlay.index("return 2;")


def test_admin_rewards_are_pulled_and_applied_automatically():
    player_ts = read(ROOT / "kingdom-in-chaos-dtp-google-player-function-v17_14_20.ts")
    assert 'action === "pull_rewards"' in player_ts
    assert 'game_google_claim_player_mail' in player_ts.split("async function pullRewards")[1][:1800]
    assert 'source: "mail"' in player_ts and 'source: "code"' in player_ts
    backend = read(SRC / "GooglePlayerBackend.java")
    assert '"pull_rewards"' in backend
    sync = read(SRC / "NativeGameRuntimeSync.java")
    assert "backend.pullRewards()" in sync and "queueCodeClaim(appCtx" in sync
    # cadangan bila function lama masih terpasang
    assert "backend.getCodeClaims()" in sync
    app = read(SRC / "DtpApp.java")
    assert "rewardPullTick" in app and "reconcileClaimedMail(active)" in app


def test_sql_mail_claim_credits_event_eyes():
    for name in ("kingdom-in-chaos-dtp-SQL-v17_14_20-hadiah-admin.sql", "kingdom-in-chaos-dtp-SQL-GABUNGAN-v17_14_20.sql"):
        sql = read(ROOT / name)
        tail = sql[sql.rindex("create or replace function public.game_google_claim_player_mail("):]
        for needle in ("v_eyes := coalesce((v_reward->>'event_eyes')::bigint, 0)", "event_eyes = event_eyes + v_eyes",
                       "v_wallet.event_eyes + v_eyes > 2147483647"):
            assert needle in tail, (name, needle)


def test_admin_panel_no_longer_tells_admin_to_wait_for_player_claim():
    html = read(ROOT / "kingdom-in-chaos-dtp-admin-v17_14_20.html")
    assert "pemain harus menekan Klaim" not in html and "Menunggu klaim" not in html
    assert 'id="mailEyes"' in html and "event_eyes: Number" in html
    assert read(ROOT / "admin.html") == html
    admin_ts = read(ROOT / "kingdom-in-chaos-dtp-game-admin-function-v17_14_20.ts")
    assert 'delivery: "auto"' in admin_ts
    for fn in ("google-player", "game-admin"):
        name = "google-player-function" if fn == "google-player" else "game-admin-function"
        assert read(ROOT / f"supabase/functions/{fn}/index.ts") == read(ROOT / f"kingdom-in-chaos-dtp-{name}-v17_14_20.ts")
