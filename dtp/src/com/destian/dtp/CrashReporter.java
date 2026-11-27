package com.destian.dtp;

import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;

import java.io.BufferedReader;
import java.io.Closeable;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Persistent crash black box for unexpected game exits.
 *
 * A session marker is kept while GameActivity is active, including ordinary pauses. On the next
 * process start it is rotated to a pending marker, then a full report is written on a worker
 * thread. The pending marker is deleted only after the report is safely written. Java uncaught
 * exceptions are synchronously saved before Android's original crash handler is called.
 */
final class CrashReporter {
    private static final String MARKER = "kic_session_marker.txt";
    private static final String PREVIOUS_MARKER = "kic_previous_session_marker.txt";
    private static final String JAVA_CRASH = "kic_last_java_crash.txt";
    private static final String REPORT = "kic_last_report.txt";
    private static final int MAX_MARKER_CHARS = 8192;
    private static final int MAX_JAVA_CRASH_CHARS = 36000;
    private static final int MAX_LOG_LINES = 1100;
    private static final int MAX_LOG_CHARS = 62000;
    private static final int MAX_REPORT_CHARS = 110000;
    private static final Object LOCK = new Object();
    private static volatile boolean handlerInstalled;

    interface ReportListener {
        void onReportReady();
    }

    private CrashReporter() { }

    /** Called from Application.onCreate. Runs only in the main application process. */
    static void onAppStart(final Context context, final ReportListener listener) {
        try {
            if (!isMainProcess(context)) return;
            final Context app = context.getApplicationContext() != null
                    ? context.getApplicationContext() : context;
            installUncaughtExceptionHandler(app);

            final String breadcrumbs;
            final String javaCrash;
            final boolean needsReport;
            synchronized (LOCK) {
                File marker = new File(app.getFilesDir(), MARKER);
                File previous = new File(app.getFilesDir(), PREVIOUS_MARKER);
                File javaFile = new File(app.getFilesDir(), JAVA_CRASH);
                if (marker.isFile()) {
                    String current = readText(marker, MAX_MARKER_CHARS);
                    String older = readText(previous, MAX_MARKER_CHARS);
                    writeText(previous, trimTail(older + current, MAX_MARKER_CHARS * 2));
                    marker.delete();
                }
                breadcrumbs = readText(previous, MAX_MARKER_CHARS * 2);
                javaCrash = readText(javaFile, MAX_JAVA_CRASH_CHARS);
                needsReport = previous.isFile() || javaFile.isFile();
            }

            if (!needsReport) return;
            Thread worker = new Thread(new Runnable() {
                @Override public void run() {
                    boolean saved = buildReport(app, breadcrumbs, javaCrash);
                    if (saved) {
                        synchronized (LOCK) {
                            new File(app.getFilesDir(), PREVIOUS_MARKER).delete();
                            new File(app.getFilesDir(), JAVA_CRASH).delete();
                        }
                        if (listener != null) {
                            new Handler(Looper.getMainLooper()).post(new Runnable() {
                                @Override public void run() {
                                    try { listener.onReportReady(); } catch (Throwable ignored) { }
                                }
                            });
                        }
                    }
                }
            }, "kic-crash-report");
            worker.setDaemon(true);
            worker.start();
        } catch (Throwable ignored) {
            // Diagnostics must never prevent the original game from starting.
        }
    }

    /** Persist Java fatal details before delegating to Android's existing crash handler. */
    private static void installUncaughtExceptionHandler(final Context context) {
        if (handlerInstalled) return;
        synchronized (LOCK) {
            if (handlerInstalled) return;
            final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
            Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
                @Override public void uncaughtException(Thread thread, Throwable error) {
                    saveJavaCrash(context, thread, error);
                    if (previous != null) {
                        previous.uncaughtException(thread, error);
                    } else {
                        Process.killProcess(Process.myPid());
                        System.exit(10);
                    }
                }
            });
            handlerInstalled = true;
        }
    }

    private static void saveJavaCrash(Context context, Thread thread, Throwable error) {
        try {
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            pw.println("JAVA UNCAUGHT EXCEPTION");
            pw.println("Waktu: " + stamp());
            pw.println("Thread: " + (thread == null ? "unknown" : thread.getName())
                    + " | id=" + (thread == null ? -1 : thread.getId()));
            if (error != null) error.printStackTrace(pw);
            pw.flush();
            String text = sw.toString();
            if (text.length() > MAX_JAVA_CRASH_CHARS) {
                text = text.substring(0, MAX_JAVA_CRASH_CHARS);
            }
            synchronized (LOCK) {
                writeText(new File(context.getFilesDir(), JAVA_CRASH), text);
            }
        } catch (Throwable ignored) {
            // Last-resort crash path: never interfere with the system crash handler.
        }
    }

    /** Add a timestamped breadcrumb to the current game session. */
    static void mark(Context context, String event) {
        try {
            synchronized (LOCK) {
                File file = new File(context.getFilesDir(), MARKER);
                String text = readText(file, MAX_MARKER_CHARS) + stamp() + " " + event + "\n";
                writeText(file, trimTail(text, MAX_MARKER_CHARS));
            }
        } catch (Throwable ignored) { }
    }

    /** Clear only for an explicitly normal game exit or the intentional maintenance kick. */
    static void clearMarker(Context context) {
        try {
            synchronized (LOCK) {
                new File(context.getFilesDir(), MARKER).delete();
            }
        } catch (Throwable ignored) { }
    }

    /** Read the saved report; it is retained until the player explicitly deletes it. */
    static String peekReport(Context context) {
        try {
            File file = new File(context.getFilesDir(), REPORT);
            if (!file.isFile()) return null;
            String text = readText(file, MAX_REPORT_CHARS + 4096);
            return text.length() == 0 ? null : text;
        } catch (Throwable ignored) {
            return null;
        }
    }

    static void deleteReport(Context context) {
        try {
            new File(context.getFilesDir(), REPORT).delete();
        } catch (Throwable ignored) { }
    }

    private static boolean isMainProcess(Context context) {
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new FileReader("/proc/self/cmdline"));
            String name = reader.readLine();
            if (name == null) return true;
            int nul = name.indexOf('\0');
            if (nul >= 0) name = name.substring(0, nul);
            return name.trim().equals(context.getPackageName());
        } catch (Throwable ignored) {
            return true;
        } finally {
            closeQuietly(reader);
        }
    }

    private static boolean buildReport(Context context, String breadcrumbs, String javaCrash) {
        StringBuilder sb = new StringBuilder();
        try {
            sb.append("LAPORAN LENGKAP GAME KELUAR SENDIRI - Kingdom In Chaos DTP v17.11\n");
            sb.append("Waktu laporan: ").append(stamp()).append('\n');
            sb.append("Package: ").append(context.getPackageName()).append('\n');
            sb.append("PID saat laporan: ").append(Process.myPid()).append('\n');
            sb.append("Perangkat: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                    .append(" | device=").append(Build.DEVICE)
                    .append(" | hardware=").append(Build.HARDWARE).append('\n');
            sb.append("Android: ").append(Build.VERSION.RELEASE)
                    .append(" | API ").append(Build.VERSION.SDK_INT)
                    .append(" | build=").append(Build.DISPLAY).append('\n');
            sb.append("Build fingerprint: ").append(Build.FINGERPRINT).append('\n');
            sb.append("Aplikasi: ").append(appVersion(context)).append('\n');
            sb.append("ABI: ");
            String[] abis = Build.SUPPORTED_ABIS;
            for (int i = 0; abis != null && i < abis.length; i++) {
                if (i > 0) sb.append(',');
                sb.append(abis[i]);
            }
            sb.append("\n\n== JEJAK SESI SEBELUMNYA ==\n");
            sb.append(breadcrumbs.length() == 0 ? "(penanda sesi tidak tersedia; detail exit Android tetap diperiksa)\n" : redact(breadcrumbs));

            if (javaCrash.length() > 0) {
                sb.append("\n== JAVA CRASH: EXCEPTION DAN STACK TRACE ==\n");
                sb.append(redact(javaCrash)).append('\n');
            } else {
                sb.append("\n== JAVA CRASH ==\n(tidak ada uncaught exception Java yang tersimpan)\n");
            }

            if (Build.VERSION.SDK_INT >= 30) {
                sb.append("\n== RIWAYAT ALASAN PROSES MENURUT ANDROID ==\n");
                sb.append(ExitInfo.describe(context));
            } else {
                sb.append("\n== RIWAYAT ALASAN PROSES ANDROID ==\n");
                sb.append("ApplicationExitInfo memerlukan Android 11 (API 30) atau lebih baru.\n");
            }

            sb.append("\n== LOG SISTEM YANG RELEVAN (LOGCAT) ==\n");
            sb.append(collectLog());
            sb.append("\n== CATATAN AKSES LOG ==\n");
            sb.append("Android dapat membatasi akses aplikasi ke log sistem. Jika logcat kosong/ditolak, "
                    + "bagian Java exception dan ApplicationExitInfo tetap dicoba secara terpisah.\n");
            sb.append("Laporan ini tidak mengirim data ke server. File disimpan lokal di penyimpanan privat aplikasi.\n");
        } catch (Throwable error) {
            sb.append("\n[ sebagian laporan gagal disusun: ").append(error).append(" ]\n");
        }

        String text = sb.toString();
        if (text.length() > MAX_REPORT_CHARS) {
            text = text.substring(0, 12000) + "\n...[bagian tengah dipotong karena batas penyimpanan laporan]...\n"
                    + text.substring(text.length() - (MAX_REPORT_CHARS - 12000));
        }
        try {
            synchronized (LOCK) {
                File report = new File(context.getFilesDir(), REPORT);
                File temp = new File(context.getFilesDir(), REPORT + ".tmp");
                writeText(temp, text);
                if (report.exists() && !report.delete()) return false;
                if (!temp.renameTo(report)) {
                    copyFile(temp, report);
                    temp.delete();
                }
                return report.isFile() && report.length() > 0;
            }
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static String appVersion(Context context) {
        try {
            PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            long code = Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
            return String.valueOf(info.versionName) + " (versionCode=" + code + ")";
        } catch (Throwable error) {
            return "tidak tersedia: " + error;
        }
    }

    private static String collectLog() {
        java.lang.Process process = null;
        BufferedReader reader = null;
        try {
            ProcessBuilder builder = new ProcessBuilder("logcat", "-d", "-v", "threadtime", "-t", "5000");
            builder.redirectErrorStream(true);
            process = builder.start();
            reader = new BufferedReader(new InputStreamReader(process.getInputStream(), "UTF-8"));
            ArrayList<String> keep = new ArrayList<String>();
            String line;
            while ((line = reader.readLine()) != null) {
                if (interesting(line)) {
                    keep.add(redact(line.length() > 700 ? line.substring(0, 700) : line));
                }
            }
            process.waitFor();
            int from = Math.max(0, keep.size() - MAX_LOG_LINES);
            StringBuilder out = new StringBuilder();
            for (int i = from; i < keep.size(); i++) out.append(keep.get(i)).append('\n');
            if (out.length() == 0) return "(tidak ada baris relevan yang bisa dibaca; akses logcat mungkin dibatasi Android)\n";
            if (out.length() > MAX_LOG_CHARS) return out.substring(out.length() - MAX_LOG_CHARS);
            return out.toString();
        } catch (Throwable error) {
            return "(logcat tidak bisa dibaca: " + error + ")\n";
        } finally {
            closeQuietly(reader);
            if (process != null) {
                try { process.destroy(); } catch (Throwable ignored) { }
            }
        }
    }

    private static boolean interesting(String line) {
        String l = line == null ? "" : line;
        return l.contains("FATAL") || l.contains("Fatal signal") || l.contains("AndroidRuntime")
                || l.contains("backtrace") || l.contains("libgame") || l.contains("JNI DETECTED")
                || l.contains("Aborting") || l.contains("SIGSEGV") || l.contains("SIGABRT")
                || l.contains("DEBUG") || l.contains("Exception") || l.contains("Error")
                || l.contains("ANR") || l.contains("KIC") || l.contains("CrossPromotion")
                || l.contains("cocos2d") || l.contains("NetworkOnMainThreadException")
                || l.contains("com.destian.kingdominchaosdtp")
                || l.contains(" E ") || l.contains(" F ");
    }

    /** Kept nested so ApplicationExitInfo is only resolved on Android 11+ devices. */
    private static final class ExitInfo {
        static String describe(Context context) {
            StringBuilder sb = new StringBuilder();
            try {
                ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
                if (am == null) return "ActivityManager tidak tersedia\n";
                List<android.app.ApplicationExitInfo> list =
                        am.getHistoricalProcessExitReasons(context.getPackageName(), 0, 8);
                if (list == null || list.isEmpty()) return "(Android tidak menyediakan riwayat exit)\n";
                for (android.app.ApplicationExitInfo info : list) {
                    sb.append(stampMs(info.getTimestamp()))
                            .append(" pid=").append(info.getPid())
                            .append(" proses=").append(info.getProcessName())
                            .append(" alasan=").append(reasonName(info.getReason()))
                            .append('(').append(info.getReason()).append(')')
                            .append(" status=").append(info.getStatus())
                            .append(" importance=").append(info.getImportance())
                            .append(" pssKB=").append(info.getPss())
                            .append(" rssKB=").append(info.getRss());
                    String description = info.getDescription();
                    if (description != null) sb.append(" keterangan=").append(redact(description));
                    sb.append('\n');
                    String trace = readTrace(info);
                    if (trace.length() > 0) sb.append(trace);
                }
            } catch (Throwable error) {
                sb.append("Gagal membaca ApplicationExitInfo: ").append(error).append('\n');
            }
            return sb.toString();
        }

        private static String readTrace(android.app.ApplicationExitInfo info) {
            InputStream in = null;
            try {
                in = info.getTraceInputStream();
                if (in == null) return "";
                byte[] buf = new byte[24576];
                int total = 0;
                int n;
                while (total < buf.length && (n = in.read(buf, total, buf.length - total)) > 0) total += n;
                StringBuilder out = new StringBuilder("  [detail trace/tombstone yang dapat dibaca]\n");
                boolean lastBreak = true;
                int runStart = out.length();
                for (int i = 0; i < total; i++) {
                    int b = buf[i] & 0xFF;
                    if ((b >= 32 && b < 127) || b == '\n' || b == '\t') {
                        out.append((char) b);
                        lastBreak = (b == '\n');
                    } else if (!lastBreak) {
                        out.append('\n');
                        lastBreak = true;
                    }
                }
                return out.length() > runStart ? redact(out.toString()) + "\n" : "";
            } catch (Throwable error) {
                return "  (trace/tombstone tidak bisa dibaca: " + error + ")\n";
            } finally {
                closeQuietly(in);
            }
        }

        private static String reasonName(int reason) {
            switch (reason) {
                case 1: return "EXIT_SELF";
                case 2: return "SIGNALED";
                case 3: return "LOW_MEMORY";
                case 4: return "CRASH_JAVA";
                case 5: return "CRASH_NATIVE";
                case 6: return "ANR";
                case 7: return "INITIALIZATION_FAILURE";
                case 8: return "PERMISSION_CHANGE";
                case 9: return "EXCESSIVE_RESOURCE_USAGE";
                case 10: return "USER_REQUESTED";
                case 11: return "USER_STOPPED";
                case 12: return "DEPENDENCY_DIED";
                case 13: return "OTHER";
                default: return "UNKNOWN";
            }
        }
    }

    private static String redact(String input) {
        if (input == null) return "";
        return input.replaceAll("(?i)(authorization\\s*[:=]\\s*bearer\\s+)[^\\s,;]+", "$1[REDACTED]")
                .replaceAll("(?i)((?:access_token|refresh_token|id_token|client_secret|service_role|apikey|api_key|password)\\s*[=:]\\s*)[^\\s,;&]+", "$1[REDACTED]");
    }

    private static String trimTail(String text, int max) {
        if (text == null || text.length() <= max) return text == null ? "" : text;
        return text.substring(text.length() - max);
    }

    private static void copyFile(File source, File target) throws IOException {
        FileInputStream in = null;
        FileOutputStream out = null;
        try {
            in = new FileInputStream(source);
            out = new FileOutputStream(target, false);
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) > 0) out.write(buffer, 0, count);
            out.flush();
        } finally {
            closeQuietly(in);
            closeQuietly(out);
        }
    }

    private static String stamp() {
        return stampMs(System.currentTimeMillis());
    }

    private static String stampMs(long millis) {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(new Date(millis));
    }

    private static String readText(File file, int maxChars) throws IOException {
        if (!file.isFile()) return "";
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            char[] buf = new char[4096];
            int n;
            while (sb.length() < maxChars && (n = reader.read(buf)) > 0) sb.append(buf, 0, n);
            return sb.toString();
        } finally {
            closeQuietly(reader);
        }
    }

    private static void writeText(File file, String text) throws IOException {
        OutputStreamWriter writer = null;
        try {
            writer = new OutputStreamWriter(new FileOutputStream(file, false), "UTF-8");
            writer.write(text);
            writer.flush();
        } finally {
            closeQuietly(writer);
        }
    }

    private static void closeQuietly(Closeable closeable) {
        if (closeable == null) return;
        try { closeable.close(); } catch (Throwable ignored) { }
    }
}
