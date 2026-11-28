"""v17.14.19: Hub/Surat/Daging dihapus; Kode Hadiah langsung dari tombol game; hadiah diatur admin."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "dtp/src/com/destian/dtp"


def read(path):
    return Path(path).read_text(encoding="utf-8")


def test_hub_mail_meat_screens_are_removed_everywhere():
    for name in ("GameOnlineHubActivity", "GameMailActivity", "GameMeatActivity"):
        assert not (SRC / f"{name}.java").exists(), name
        manifest = read(ROOT / "kingdom-in-chaos-decompiled/AndroidManifest.xml")
        assert name not in manifest
        for java in SRC.glob("*.java"):
            assert name not in read(java), f"{name} masih dirujuk di {java.name}"
    assert "GameGiftCodeActivity" in read(ROOT / "kingdom-in-chaos-decompiled/AndroidManifest.xml")


def test_game_kode_hadiah_button_opens_gift_code_screen_directly():
    overlay = read(SRC / "GameOnlineOverlay.java")
    assert "return 3;" in overlay
    assert "GameGiftCodeActivity.class" in overlay
    # zona Kode Hadiah harus dicek sebelum kotak avatar yang bertumpuk dengannya
    assert overlay.index("return 3;") < overlay.index("return 2;")
    # bawah-kiri layar Toko: tombol asli ada di sekitar x 0.18-0.34H, y 0.93-1.0H
    m = re.search(r"x >= ([0-9.]+)f \* h && x <= ([0-9.]+)f \* h && y >= ([0-9.]+)f \* h && y <= ([0-9.]+)f \* h\) return 3;", overlay)
    assert m
    x0, x1, y0, y1 = map(float, m.groups())
    assert x0 <= 0.176 and x1 >= 0.343 and y0 <= 0.93 and y1 >= 0.99


def test_redeemed_rewards_are_queued_for_native_wallet_and_recovered():
    gift = read(SRC / "GameGiftCodeActivity.java")
    assert "queueCodeClaim" in gift and '"claim"' in gift
    sync = read(SRC / "NativeGameRuntimeSync.java")
    assert "static boolean queueCodeClaim" in sync and "getCodeClaims()" in sync
    assert "get_code_claims" in read(SRC / "GooglePlayerBackend.java")


def test_sql_redeem_credits_event_eyes_and_returns_claim():
    sql = read(ROOT / "kingdom-in-chaos-dtp-SQL-v17_14_19-kode-hadiah.sql")
    for needle in ("event_eyes = event_eyes + v_eyes", "native_credit", "'claim_id', v_claim_id", "'rewards', v_reward"):
        assert needle in sql, needle


def test_functions_and_admin_support_four_reward_types():
    admin_ts = read(ROOT / "kingdom-in-chaos-dtp-game-admin-function-v17_14_19.ts")
    assert '"event_eyes"' in admin_ts.split("function validateRewardConfig")[1][:400]
    player_ts = read(ROOT / "kingdom-in-chaos-dtp-google-player-function-v17_14_19.ts")
    assert 'action === "get_code_claims"' in player_ts and '.eq("native_credit", true)' in player_ts
    html = read(ROOT / "kingdom-in-chaos-dtp-admin-v17_14_19.html")
    for fid in ("rewardEyes", "rewardDM", "rewardCoins", "rewardGoblin"):
        assert f'id="{fid}"' in html
    assert "rewardMeat" not in html and "event_eyes: Number" in html
