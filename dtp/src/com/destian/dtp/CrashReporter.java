package com.destian.dtp;

import android.app.ActivityManager;
import android.content.Context;
import android.os.Build;

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
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Kotak hitam ringan untuk kasus "game keluar sendiri".
 *
 * Cara kerja: saat GameActivity tampil ditulis penanda sesi; saat GameActivity pause secara
 * normal penanda dihapus. Jika proses berikutnya menemukan penanda yang masih ada, berarti sesi
 * sebelumnya berakhir tidak wajar (crash Java/native, dimatikan sistem). Saat itu disusun laporan
 * teks (jejak sesi, alasan keluar dari Android 11+, dan log relevan) yang bisa dibuka dan disalin
 * dari tombol LAPORAN CRASH di overlay game. Semua metode aman dipanggil kapan saja: tidak ada
 * exception yang keluar ke pemanggil.
 */
final class CrashReporter {
    private static final String MARKER = "kic_session_marker.txt";
    private static final String REPORT = "kic_last_report.txt";
    private static final int MAX_MARKER_CHARS = 4096;
    private static final int MAX_LOG_LINES = 220;
    private static final int MAX_LOG_CHARS = 14000;
    private static final int MAX_REPORT_CHARS = 26000;
    private static final Object LOCK = new Object();

    private CrashReporter() { }

    /** Dipanggil dari Application.onCreate. Hanya bekerja di proses utama (bukan proses :kick). */
    static void onAppStart(final Context context) {
        try {
            if (!isMainProcess(context)) return;
            final File marker = new File(context.getFilesDir(), MARKER);
            final String breadcrumbs;
            synchronized (LOCK) {
                if (!marker.exists()) return;
                breadcrumbs = readText(marker, MAX_MARKER_CHARS);
                marker.delete();
            }
            final Context app = context.getApplicationContext() != null
                    ? context.getApplicationContext() : context;
            Thread worker = new Thread(new Runnable() {
                @Override public void run() {
                    buildReport(app, breadcrumbs);
                }
            }, "kic-crash-report");
            worker.setDaemon(true);
            worker.start();
        } catch (Throwable ignored) {
            // Perekam tidak boleh mengganggu game.
        }
    }

    /** Tambah satu baris jejak ke penanda sesi (dibuat jika belum ada). */
    static void mark(Context context, String event) {
        try {
            synchronized (LOCK) {
                File file = new File(context.getFilesDir(), MARKER);
                String text = readText(file, MAX_MARKER_CHARS) + stamp() + " " + event + "\n";
                if (text.length() > MAX_MARKER_CHARS) {
                    text = text.substring(text.length() - MAX_MARKER_CHARS);
                }
                writeText(file, text);
            }
        } catch (Throwable ignored) { }
    }

    /** Sesi berakhir wajar (pause / kick maintenance): hapus penanda supaya tidak dianggap crash. */
    static void clearMarker(Context context) {
        try {
            synchronized (LOCK) {
                new File(context.getFilesDir(), MARKER).delete();
            }
        } catch (Throwable ignored) { }
    }

    /** Isi laporan terakhir, atau null jika tidak ada. */
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

    // ---------------------------------------------------------------------------------------

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

    private static void buildReport(Context context, String breadcrumbs) {
        StringBuilder sb = new StringBuilder();
        try {
            sb.append("LAPORAN SESI TIDAK WAJAR - Kingdom In Chaos DTP v17.7\n");
            sb.append("Waktu laporan: ").append(stamp()).append('\n');
            sb.append("Perangkat: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                    .append(" | Android ").append(Build.VERSION.RELEASE)
                    .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
            sb.append("ABI: ");
            String[] abis = Build.SUPPORTED_ABIS;
            for (int i = 0; abis != null && i < abis.length; i++) {
                if (i > 0) sb.append(',');
                sb.append(abis[i]);
            }
            sb.append("\n\n== Jejak sesi sebelumnya (waktu, kejadian) ==\n").append(breadcrumbs);
            if (Build.VERSION.SDK_INT >= 30) {
                sb.append("\n== Alasan proses berakhir menurut Android ==\n");
                sb.append(ExitInfo.describe(context));
            }
            sb.append("\n== Log relevan (logcat) ==\n");
            sb.append(collectLog());
        } catch (Throwable error) {
            sb.append("\n[Sebagian laporan gagal disusun: ").append(error).append("]\n");
        }
        String text = sb.toString();
        if (text.length() > MAX_REPORT_CHARS) {
            text = text.substring(0, 8000) + "\n...[dipotong]...\n"
                    + text.substring(text.length() - (MAX_REPORT_CHARS - 8000));
        }
        try {
            synchronized (LOCK) {
                writeText(new File(context.getFilesDir(), REPORT), text);
            }
        } catch (Throwable ignored) { }
    }

    private static String collectLog() {
        Process process = null;
        BufferedReader reader = null;
        try {
            ProcessBuilder builder = new ProcessBuilder("logcat", "-d", "-v", "threadtime", "-t", "3000");
            builder.redirectErrorStream(true);
            process = builder.start();
            reader = new BufferedReader(new InputStreamReader(process.getInputStream(), "UTF-8"));
            ArrayList<String> keep = new ArrayList<String>();
            String line;
            while ((line = reader.readLine()) != null) {
                if (interesting(line)) {
                    keep.add(line.length() > 400 ? line.substring(0, 400) : line);
                }
            }
            int from = Math.max(0, keep.size() - MAX_LOG_LINES);
            StringBuilder out = new StringBuilder();
            for (int i = from; i < keep.size(); i++) {
                out.append(keep.get(i)).append('\n');
            }
            if (out.length() == 0) return "(tidak ada baris log relevan yang bisa dibaca)\n";
            if (out.length() > MAX_LOG_CHARS) {
                return out.substring(out.length() - MAX_LOG_CHARS);
            }
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

    private static boolean interesting(String l) {
        return l.contains("FATAL") || l.contains("Fatal signal") || l.contains("AndroidRuntime")
                || l.contains("backtrace") || l.contains("libgame") || l.contains("JNI DETECTED")
                || l.contains("Aborting") || l.contains("SIGSEGV") || l.contains("SIGABRT")
                || l.contains("DEBUG") || l.contains("Exception") || l.contains("Error")
                || l.contains("KIC") || l.contains("CrossPromotion") || l.contains("ocos2d")
                || l.contains(" E ") || l.contains(" F ")
                || (l.contains(" be ") && l.indexOf(':') > 0)
                || (l.contains(" dh ") && l.indexOf(':') > 0);
    }

    /** Dipisah ke kelas sendiri supaya kelas ApplicationExitInfo (API 30) hanya dimuat di Android 11+. */
    private static final class ExitInfo {
        static String describe(Context context) {
            StringBuilder sb = new StringBuilder();
            try {
                ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
                if (am == null) return "ActivityManager tidak tersedia\n";
                List<android.app.ApplicationExitInfo> list = am.getHistoricalProcessExitReasons(null, 0, 4);
                if (list == null || list.isEmpty()) return "(tidak ada data)\n";
                for (android.app.ApplicationExitInfo info : list) {
                    sb.append(stampMs(info.getTimestamp()))
                            .append(" proses=").append(info.getProcessName())
                            .append(" alasan=").append(reasonName(info.getReason()))
                            .append('(').append(info.getReason()).append(')')
                            .append(" status=").append(info.getStatus())
                            .append(" importance=").append(info.getImportance());
                    String description = info.getDescription();
                    if (description != null) sb.append(" ket=").append(description);
                    sb.append('\n');
                    if (info.getReason() == 5) { // REASON_CRASH_NATIVE
                        sb.append(readTrace(info));
                    }
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
                byte[] buf = new byte[8192];
                int total = 0;
                int n;
                while (total < buf.length && (n = in.read(buf, total, buf.length - total)) > 0) {
                    total += n;
                }
                StringBuilder out = new StringBuilder("  [tombstone native, teks yang terbaca]\n");
                boolean lastBreak = true;
                int runStart = out.length();
                for (int i = 0; i < total; i++) {
                    int b = buf[i] & 0xFF;
                    if ((b >= 32 && b < 127) || b == '\n') {
                        out.append((char) b);
                        lastBreak = (b == '\n');
                    } else if (!lastBreak) {
                        out.append('\n');
                        lastBreak = true;
                    }
                }
                return out.toString().length() > runStart ? out.toString() + "\n" : "";
            } catch (Throwable error) {
                return "  (tombstone tidak bisa dibaca: " + error + ")\n";
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
            char[] buf = new char[2048];
            int n;
            while (sb.length() < maxChars && (n = reader.read(buf)) > 0) {
                sb.append(buf, 0, n);
            }
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
        try {
            closeable.close();
        } catch (Throwable ignored) { }
    }
}
