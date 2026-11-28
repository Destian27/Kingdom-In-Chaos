from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_crash_reporter_rotates_marker_and_keeps_pending_until_saved():
    source = read("dtp/src/com/destian/dtp/CrashReporter.java")
    assert "PREVIOUS_MARKER" in source
    assert "writeText(previous" in source
    assert "if (saved)" in source
    assert "new File(app.getFilesDir(), PREVIOUS_MARKER).delete()" in source
    assert "renameTo(report)" in source


def test_java_fatal_exception_is_saved_and_original_handler_is_chained():
    source = read("dtp/src/com/destian/dtp/CrashReporter.java")
    assert "Thread.setDefaultUncaughtExceptionHandler" in source
    assert "saveJavaCrash(context, thread, error)" in source
    assert "previous.uncaughtException(thread, error)" in source
    assert "printStackTrace(pw)" in source


def test_full_report_contains_platform_exit_traces_and_redaction():
    source = read("dtp/src/com/destian/dtp/CrashReporter.java")
    assert "getHistoricalProcessExitReasons(context.getPackageName(), 0, 8)" in source
    assert "getTraceInputStream()" in source
    assert "ProcessBuilder(\"logcat\"" in source
    assert "MAX_LOG_LINES = 1100" in source
    assert "MAX_REPORT_CHARS = 110000" in source
    assert "refreshCrashReportUi" not in source  # UI callback is wired by DtpApp
    assert "access_token" in source and "refresh_token" in source and "client_secret" in source


def test_dtpapp_keeps_marker_during_pause_and_notifies_ui_when_report_is_ready():
    source = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "CrashReporter.onAppStart(this, new CrashReporter.ReportListener()" in source
    assert "GameOnlineOverlay.refreshCrashReportUi(active)" in source
    assert 'CrashReporter.mark(this, "game resumed; activity="' in source
    pause = source[source.index("public void onActivityPaused(Activity a)"):source.index("@Override public void onActivityCreated")]
    assert 'CrashReporter.mark(this, "game paused;' in pause
    assert "CrashReporter.clearMarker(this)" not in pause
    assert "a.isFinishing()" in source
    assert "kick(a);" in source and "FLAG_NOT_TOUCHABLE" in source


def test_overlay_auto_shows_full_report_and_keeps_small_reopen_icon():
    source = read("dtp/src/com/destian/dtp/GameOnlineOverlay.java")
    assert "showPendingCrashReport(activity)" in source
    assert "last_auto_shown_signature" in source
    assert "refreshCrashReportUi" in source
    assert 'button.setText("!")' in source
    assert 'setPositiveButton("Salin Semua"' in source
    assert 'setNeutralButton("Hapus Laporan"' in source
    assert "LAPORAN LENGKAP FORCE CLOSE" in source
    assert "setPrimaryClip" in source


def test_android_package_version_is_v17_14_2_google_mail_crashfix():
    source = read("kingdom-in-chaos-decompiled/apktool.yml")
    assert "versionCode: 108" in source
    assert "versionName: 1.0.8" in source
    build = read("build_dtp.py")
    assert "KingdomInChaosDTP-v1.0.8.apk" in build


def test_maintenance_gate_and_realtime_fix_remain_intact():
    app = read("dtp/src/com/destian/dtp/DtpApp.java")
    assert "if (!r.ok)" in app
    realtime = read("dtp/src/com/destian/dtp/RealtimeClient.java")
    stop = realtime[realtime.index("synchronized void stop()"):realtime.index("private void closeAsync()")]
    assert "closeQuietly()" not in stop
    assert "closeAsync();" in stop
    assert "kic-realtime-close" in realtime
