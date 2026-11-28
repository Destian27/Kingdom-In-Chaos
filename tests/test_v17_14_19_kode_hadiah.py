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


def test_game_kode_hadiah_button_opens_original_dialog_since_v17_14_20():
    # v17.14.20 mengembalikan dialog asli game; kodenya diklaim lewat hook native (lihat test_v17_14_20).
    overlay = read(SRC / "GameOnlineOverlay.java")
    assert "return 3;" not in overlay
    assert "handlePromoCode" in overlay


def test_redeemed_rewards_are_queued_for_native_wallet_and_recovered():
    gift = read(SRC / "GameGiftCodeActivity.java")
    assert "queueCodeClaim" in gift and '"claim"' in gift
    assert "queueCodeClaim" in read(SRC / "GameOnlineOverlay.java")
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
