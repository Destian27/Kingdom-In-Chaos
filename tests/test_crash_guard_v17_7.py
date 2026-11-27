from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def read(rel): return (ROOT / rel).read_text(encoding="utf-8")

def test_crash_reporter_is_main_process_only_and_never_throws():
    s = read("dtp/src/com/destian/dtp/CrashReporter.java")
    assert "/proc/self/cmdline" in s
    assert "getHistoricalProcessExitReasons" in s
    assert "ProcessBuilder(\"logcat\"" in s
    # ApplicationExitInfo hanya di kelas bersarang agar tidak dimuat di Android < 11
    assert "private static final class ExitInfo" in s
    assert "Build.VERSION.SDK_INT >= 30" in s

def test_dtpapp_wires_crash_reporter_and_catches_throwable():
    s = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "CrashReporter.onAppStart(this)" in s
    assert "CrashReporter.mark(this, \"game resumed\")" in s
    assert s.count("CrashReporter.clearMarker(this)") == 2  # kick() dan onActivityPaused()
    assert "private void onGameResumed(Activity a)" in s
    assert "catch (Exception ignored)" not in s
    assert s.count("catch (Throwable ignored)") == 6

def test_overlay_crash_report_entry():
    s = read("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "TAG_CRASH_REPORT_BUTTON" in s
    assert "CrashReporter.peekReport" in s
    assert "LAPORAN CRASH" in s
    assert "setPrimaryClip" in s

def test_kick_and_maintenance_gate_untouched():
    s = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "kick(a);" in s and "FLAG_NOT_TOUCHABLE" in s
    assert "if (!r.ok)" in s
