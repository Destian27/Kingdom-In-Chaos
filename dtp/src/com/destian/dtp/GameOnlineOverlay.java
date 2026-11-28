package com.destian.dtp;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.lang.ref.WeakReference;
import java.text.NumberFormat;
import java.util.Locale;

/** Game account entry overlay. It opens direct Google sign-in before online account tools. */
public final class GameOnlineOverlay {
    private static final String TAG_ACCOUNT_BUTTON = "com.destian.dtp.GAME_ACCOUNT_BUTTON";
    private static final String TAG_MAIL_BUTTON = "com.destian.dtp.GAME_MAIL_BUTTON";
    private static final String TAG_CAVE_BOSS_STATUS = "com.destian.dtp.CAVE_BOSS_STATUS";
    private static final String TAG_EVENT_STORE_BUTTON = "com.destian.dtp.EVENT_STORE_BUTTON";
    private static final String TAG_CRASH_REPORT_BUTTON = "com.destian.dtp.CRASH_REPORT_BUTTON";
    private static final String TAG_HOTSPOTS = "com.destian.dtp.GAME_HOTSPOTS";
    private static final String TAG_BARTER_BUTTON = "com.destian.dtp.BARTER_BUTTON";
    private static volatile WeakReference<Activity> activeActivity = new WeakReference<>(null);

    private GameOnlineOverlay() { }

    public static void install(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        try {
            View content = activity.findViewById(android.R.id.content);
            if (!(content instanceof FrameLayout)) return;
            final FrameLayout root = (FrameLayout) content;
            activeActivity = new WeakReference<>(activity);

            // v17.14.8: tombol GOOGLE, SURAT, dan BARTER dihapus (sudah ada di dalam game).
            removeLegacyButtons(root);
            if (root.findViewWithTag(TAG_HOTSPOTS) == null) {
                root.addView(new Hotspots(activity), new FrameLayout.LayoutParams(-1, -1));
            }

            Button eventButton = (Button) root.findViewWithTag(TAG_EVENT_STORE_BUTTON);
            if (eventButton == null) {
                eventButton = new Button(activity);
                eventButton.setTag(TAG_EVENT_STORE_BUTTON);
                eventButton.setText("EVENT SHOP");
                eventButton.setTextSize(10f);
                eventButton.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                eventButton.setAllCaps(false);
                eventButton.setAlpha(0.96f);
                eventButton.setVisibility(View.GONE);
                eventButton.setContentDescription("Open the scheduled event shop");
                eventButton.setOnClickListener(new View.OnClickListener() {
                    @Override public void onClick(View view) {
                        try {
                            activity.startActivity(new Intent(activity, GameEventStoreActivity.class));
                        } catch (RuntimeException ignored) { }
                    }
                });
                FrameLayout.LayoutParams eventParams = new FrameLayout.LayoutParams(
                        dp(activity, 112), dp(activity, 40), Gravity.TOP | Gravity.RIGHT);
                eventParams.topMargin = dp(activity, 54);
                eventParams.rightMargin = dp(activity, 8);
                root.addView(eventButton, eventParams);
                eventButton.bringToFront();
            }
            addCrashReportEntry(activity, root);
            installEconomyHooksLater(activity, root, 0);
            showPendingCrashReport(activity);
        } catch (Throwable ignored) {
            // The original native game keeps working if an optional overlay cannot be added.
        }
    }


    /**
     * v17.14.8: area sentuh tak terlihat di atas tombol bawaan game.
     * Tombol LOGIN (kiri atas) membuka pemilih akun Google, atau dialog akun bila sudah login.
     * v17.14.19: Hub Online, Surat, dan Daging Misi DIHAPUS. Tombol KODE HADIAH asli game (kiri bawah
     * layar Toko) kini langsung membuka halaman klaim kode.
     * v17.14.18: area Bakat DIHAPUS agar tombol Bakat asli game (menu kanan) berfungsi lagi.
     * Sentuhan di luar area tidak dikonsumsi sehingga game tetap menerimanya.
     * Koordinat relatif terhadap tinggi layar.
     */
    private static final class Hotspots extends View {
        private final Activity activity;
        private int downZone = -1;

        Hotspots(Activity activity) {
            super(activity);
            this.activity = activity;
            setTag(TAG_HOTSPOTS);
        }

        /** 0 = LOGIN, 2 = avatar/nama panggilan, 3 = Kode Hadiah, -1 = di luar area (1 = Bakat, tidak dipakai). */
        private int zoneAt(float x, float y) {
            float h = getHeight(), w = getWidth();
            if (h <= 0 || w <= 0) return -1;
            // v17.14.19: tombol "Kode Hadiah" asli game (pojok kiri bawah Toko). Dicek lebih dulu
            // dari kotak avatar karena sebagian areanya bertumpuk.
            if (x >= 0.15f * h && x <= 0.37f * h && y >= 0.92f * h && y <= 1.0f * h) return 3;
            // LOGIN: kiri 0.020H, atas 0.138H, lebar 0.264H, tinggi 0.107H
            if (x >= 0.020f * h && x <= 0.284f * h && y >= 0.138f * h && y <= 0.245f * h) return 0;
            // v17.14.10: kotak avatar + nama panggilan (kiri bawah beranda) -> Google lebih dulu,
            // lalu layar Daftar (nama saja). Dialog Masuk/Daftar bawaan game tidak lagi terbuka.
            if (x >= 0.085f * h && x <= 0.68f * h && y >= 0.80f * h && y <= 0.975f * h) return 2;
            return -1;
        }

        @Override public boolean onTouchEvent(MotionEvent e) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downZone = zoneAt(e.getX(), e.getY());
                    return downZone >= 0;
                case MotionEvent.ACTION_UP:
                    int zone = downZone;
                    downZone = -1;
                    if (zone >= 0 && zone == zoneAt(e.getX(), e.getY())) open(zone);
                    return zone >= 0;
                case MotionEvent.ACTION_CANCEL:
                    downZone = -1;
                    return false;
                default:
                    return downZone >= 0;
            }
        }

        private void open(int zone) {
            try {
                GooglePlayerBackend backend = new GooglePlayerBackend(activity.getApplicationContext());
                if (zone == 3) {
                    // Kode Hadiah: butuh akun Google; belum login -> pemilih akun dulu.
                    if (backend.hasAccount()) {
                        activity.startActivity(new Intent(activity, GameGiftCodeActivity.class));
                    } else {
                        Toast.makeText(activity, "Login Google dulu untuk memakai Kode Hadiah.", Toast.LENGTH_LONG).show();
                        activity.startActivity(new Intent(activity, GameAuthActivity.class));
                    }
                    return;
                }
                if (backend.hasAccount()) showAccountDialog(activity, backend);
                else activity.startActivity(new Intent(activity, GameAuthActivity.class));
            } catch (RuntimeException ignored) { }
        }
    }

    /** Dialog akun kecil pengganti Hub Online: menampilkan akun Google aktif dan tombol keluar. */
    private static void showAccountDialog(final Activity activity, final GooglePlayerBackend backend) {
        String name = backend.getSavedAccountName();
        new AlertDialog.Builder(activity)
                .setTitle("Akun Google")
                .setMessage("Masuk sebagai:\n" + (name == null || name.isEmpty() ? "-" : name))
                .setPositiveButton("Tutup", null)
                .setNegativeButton("Keluar Google", new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface dialog, int which) {
                        backend.clearAccount();
                        Toast.makeText(activity, "Sudah keluar dari akun Google.", Toast.LENGTH_SHORT).show();
                    }
                })
                .show();
    }

    private static void removeLegacyButtons(FrameLayout root) {
        String[] tags = {TAG_ACCOUNT_BUTTON, TAG_MAIL_BUTTON, TAG_BARTER_BUTTON};
        for (String tag : tags) {
            View old = root.findViewWithTag(tag);
            if (old != null) root.removeView(old);
        }
    }


    private static void installEconomyHooksLater(final Activity activity, final View root, final int attempt) {
        if (activity == null || activity.isFinishing()) return;
        String state = NativeGameRuntimeBridge.installEconomyHooks();
        if (state != null && state.startsWith("OK|")) return;
        if (attempt >= 10) {
            CrashReporter.mark(activity, "barter native hook not ready: " + state);
            return;
        }
        root.postDelayed(new Runnable() {
            @Override public void run() {
                installEconomyHooksLater(activity, root, attempt + 1);
            }
        }, 1200L);
    }

    public static void refreshBarterStatus() {
        WeakReference<Activity> ref = activeActivity;
        refreshBarterStatus(ref == null ? null : ref.get());
    }

    public static void refreshBarterStatus(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    View content = activity.findViewById(android.R.id.content);
                    if (!(content instanceof FrameLayout)) return;
                    View button = ((FrameLayout) content).findViewWithTag(TAG_BARTER_BUTTON);
                    if (button != null) {
                        long earned = NativeGameRuntimeBridge.getLifetimeDmEarned(activity);
                        button.setContentDescription("Buka barter. Total DM terkumpul: " + formatNumber(earned));
                    }
                } catch (Throwable ignored) { }
            }
        });
    }

    public static void notifyBarterResult(final int offerId, final int status) {
        WeakReference<Activity> reference = activeActivity;
        final Activity activity = reference == null ? null : reference.get();
        if (activity == null || activity.isFinishing()) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                String message;
                switch (status) {
                    case 0: message = "Barter berhasil. Hadiah diproses oleh game."; break;
                    case 1: message = "Koin tidak cukup."; break;
                    case 2: message = "DM tidak cukup."; break;
                    case 3: message = "Hadiah ini sudah pernah diklaim."; break;
                    case 5: message = "Sistem barter belum siap. Masuk ulang ke game."; break;
                    default: message = "Top up uang asli dinonaktifkan. Gunakan menu BARTER."; break;
                }
                Toast.makeText(activity, message, Toast.LENGTH_LONG).show();
            }
        });
    }

    private static void showBarterDialog(final Activity activity) {
        String wallet = NativeGameRuntimeBridge.getWallet();
        if (wallet == null || !wallet.startsWith("coins=")) {
            Toast.makeText(activity, "Saldo game belum bisa dibaca: " + wallet, Toast.LENGTH_LONG).show();
            return;
        }
        long coins = parseWalletValue(wallet, "coins=");
        long dm = parseWalletValue(wallet, "dm=");
        long earned = NativeGameRuntimeBridge.getLifetimeDmEarned(activity);

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(activity, 14), dp(activity, 8), dp(activity, 14), dp(activity, 8));
        TextView summary = new TextView(activity);
        summary.setTextColor(Color.WHITE);
        summary.setTextSize(13f);
        summary.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        summary.setText("SALDO SAAT INI\nKoin: " + formatNumber(coins)
                + "   •   DM: " + formatNumber(dm)
                + "\nTotal DM terkumpul: " + formatNumber(earned));
        summary.setPadding(0, 0, 0, dp(activity, 6));
        content.addView(summary);

        long[] milestones = {2000L, 5000L, 15000L, 50000L};
        long nextMilestone = milestones[milestones.length - 1];
        long previousMilestone = 0L;
        for (long milestone : milestones) {
            if (earned < milestone) { nextMilestone = milestone; break; }
            previousMilestone = milestone;
        }
        android.widget.ProgressBar dmProgress = new android.widget.ProgressBar(
                activity, null, android.R.attr.progressBarStyleHorizontal);
        dmProgress.setMax(1000);
        long span = Math.max(1L, nextMilestone - previousMilestone);
        int progress = (int) Math.max(0L, Math.min(1000L,
                ((earned - previousMilestone) * 1000L) / span));
        dmProgress.setProgress(progress);
        content.addView(dmProgress, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(activity, 8)));
        TextView progressLabel = new TextView(activity);
        progressLabel.setTextColor(0xFFFFD36A);
        progressLabel.setTextSize(11f);
        progressLabel.setText(earned >= milestones[milestones.length - 1]
                ? "Progres DM: semua ambang tercapai (50.000 DM)"
                : "Progres DM: " + formatNumber(earned) + " / " + formatNumber(nextMilestone)
                    + " DM  •  Ambang: 2.000 / 5.000 / 15.000 / 50.000 DM");
        progressLabel.setPadding(0, dp(activity, 4), 0, dp(activity, 10));
        content.addView(progressLabel);

        TextView exchangeTitle = sectionTitle(activity, "TUKAR MATA UANG");
        content.addView(exchangeTitle);
        addBarterOption(content, activity, 0, "200 DM  →  10.000 Koin");
        addBarterOption(content, activity, 1, "700 DM  →  35.000 Koin");
        addBarterOption(content, activity, 2, "2.400 DM  →  120.000 Koin");
        addBarterOption(content, activity, 3, "10.000 Koin  →  200 DM");
        addBarterOption(content, activity, 4, "35.000 Koin  →  700 DM");
        addBarterOption(content, activity, 5, "120.000 Koin  →  2.400 DM");

        content.addView(sectionTitle(activity, "PAKET DAN KEISTIMEWAAN"));
        addBarterOption(content, activity, 6, "VIP 30 hari  —  600 DM");
        addBarterOption(content, activity, 7, "Luck Spree  —  70 DM");
        addBarterOption(content, activity, 8, "Newbie Value Pack  —  299 DM");
        addBarterOption(content, activity, 9, "Newbie Rich Pack  —  999 DM");
        addBarterOption(content, activity, 18, "Paket Hero  —  560 DM");
        addBarterOption(content, activity, 19, "Paket Perlengkapan  —  420 DM");
        addBarterOption(content, activity, 20, "Paket Mingguan  —  599 DM");
        addBarterOption(content, activity, 21, "Tiket PvP  —  99 DM");
        addBarterOption(content, activity, 22, "Paket Musiman A  —  499 DM");
        addBarterOption(content, activity, 23, "Paket Musiman B  —  1.499 DM");

        content.addView(sectionTitle(activity, "PERLENGKAPAN INDIVIDUAL"));
        for (int i = 0; i < 8; i++) {
            addBarterOption(content, activity, 10 + i,
                    "Perlengkapan " + (i + 1) + "  —  499 DM");
        }

        ScrollView scroll = new ScrollView(activity);
        scroll.addView(content);
        new AlertDialog.Builder(activity)
                .setTitle("SISTEM BARTER DTP")
                .setView(scroll)
                .setNegativeButton("Tutup", null)
                .show();
    }

    private static TextView sectionTitle(Activity activity, String value) {
        TextView title = new TextView(activity);
        title.setText(value);
        title.setTextColor(0xFFFFD36A);
        title.setTextSize(12f);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setPadding(0, dp(activity, 10), 0, dp(activity, 4));
        return title;
    }

    private static void addBarterOption(LinearLayout parent, final Activity activity,
                                        final int offerId, final String label) {
        Button option = new Button(activity);
        option.setText(label);
        option.setAllCaps(false);
        option.setTextSize(12f);
        option.setTextColor(Color.WHITE);
        option.setBackground(buttonBackground());
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(activity, 42));
        params.bottomMargin = dp(activity, 5);
        parent.addView(option, params);
        option.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) {
                new AlertDialog.Builder(activity)
                        .setTitle("Konfirmasi barter")
                        .setMessage("Lanjutkan " + label + "? Saldo akan dipotong sebelum hadiah diberikan.")
                        .setPositiveButton("Tukar sekarang", new DialogInterface.OnClickListener() {
                            @Override public void onClick(DialogInterface dialog, int which) {
                                String result = NativeGameRuntimeBridge.performBarter(offerId);
                                String message;
                                if (result != null && result.startsWith("OK|")) {
                                    message = "Barter berhasil.";
                                } else if ("INSUFFICIENT_COINS".equals(result)) {
                                    message = "Koin tidak cukup.";
                                } else if ("INSUFFICIENT_DM".equals(result)) {
                                    message = "DM tidak cukup.";
                                } else if ("ALREADY_CLAIMED".equals(result)) {
                                    message = "Hadiah ini sudah pernah diklaim.";
                                } else {
                                    message = "Barter gagal: " + result;
                                }
                                Toast.makeText(activity, message, Toast.LENGTH_LONG).show();
                            }
                        })
                        .setNegativeButton("Batal", null)
                        .show();
            }
        });
    }

    private static long parseWalletValue(String wallet, String prefix) {
        try {
            int start = wallet.indexOf(prefix);
            if (start < 0) return 0L;
            start += prefix.length();
            int end = wallet.indexOf(';', start);
            if (end < 0) end = wallet.length();
            return Long.parseLong(wallet.substring(start, end).trim());
        } catch (RuntimeException ignored) { return 0L; }
    }

    private static String formatNumber(long value) {
        return NumberFormat.getIntegerInstance(new Locale("id", "ID")).format(value);
    }

    /** Refresh the small report icon and automatically show a newly saved report. */
    public static void refreshCrashReportUi(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    View content = activity.findViewById(android.R.id.content);
                    if (content instanceof FrameLayout) {
                        addCrashReportEntry(activity, (FrameLayout) content);
                    }
                    showPendingCrashReport(activity);
                } catch (Throwable ignored) { }
            }
        });
    }

    /** Automatically display the saved report once per app process/report. */
    public static void showPendingCrashReport(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        try {
            final String report = CrashReporter.peekReport(activity.getApplicationContext());
            if (report == null) return;
            final String key = Integer.toHexString(report.hashCode()) + ":" + report.length();
            SharedPreferences prefs = activity.getSharedPreferences("kic_crash_reports", Context.MODE_PRIVATE);
            if (key.equals(prefs.getString("last_auto_shown_signature", ""))) return;
            prefs.edit().putString("last_auto_shown_signature", key).apply();
            activity.runOnUiThread(new Runnable() {
                @Override public void run() {
                    if (!activity.isFinishing()) showCrashReportDialog(activity);
                }
            });
        } catch (Throwable ignored) { }
    }

    /** Small warning icon remains available to reopen the full report later. */
    private static void addCrashReportEntry(final Activity activity, FrameLayout root) {
        try {
            View existing = root.findViewWithTag(TAG_CRASH_REPORT_BUTTON);
            String report = CrashReporter.peekReport(activity.getApplicationContext());
            if (report == null) {
                if (existing != null) root.removeView(existing);
                return;
            }
            if (existing != null) {
                existing.bringToFront();
                return;
            }
            Button button = new Button(activity);
            button.setTag(TAG_CRASH_REPORT_BUTTON);
            button.setText("!");
            button.setTextSize(19f);
            button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            button.setAllCaps(false);
            button.setTextColor(Color.WHITE);
            button.setPadding(0, 0, 0, 0);
            button.setBackground(buttonBackground());
            button.setContentDescription("Buka laporan lengkap game keluar sendiri");
            button.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) {
                    showCrashReportDialog(activity);
                }
            });
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    dp(activity, 38), dp(activity, 38), Gravity.TOP | Gravity.LEFT);
            params.topMargin = dp(activity, 102);
            params.leftMargin = dp(activity, 8);
            root.addView(button, params);
            button.bringToFront();
        } catch (Throwable ignored) { }
    }

    private static void showCrashReportDialog(final Activity activity) {
        try {
            final String report = CrashReporter.peekReport(activity.getApplicationContext());
            if (report == null) return;
            ScrollView scroll = new ScrollView(activity);
            TextView text = new TextView(activity);
            text.setText(report);
            text.setTextSize(10f);
            text.setTypeface(Typeface.MONOSPACE);
            text.setTextIsSelectable(true);
            text.setPadding(dp(activity, 12), dp(activity, 8), dp(activity, 12), dp(activity, 8));
            scroll.addView(text);
            new AlertDialog.Builder(activity)
                    .setTitle("LAPORAN LENGKAP FORCE CLOSE • v17.12")
                    .setView(scroll)
                    .setPositiveButton("Salin Semua", new DialogInterface.OnClickListener() {
                        @Override public void onClick(DialogInterface dialog, int which) {
                            try {
                                ClipboardManager clipboard = (ClipboardManager)
                                        activity.getSystemService(Context.CLIPBOARD_SERVICE);
                                if (clipboard != null) {
                                    clipboard.setPrimaryClip(ClipData.newPlainText("Laporan KIC DTP v17.12", report));
                                    Toast.makeText(activity, "Laporan lengkap disalin", Toast.LENGTH_SHORT).show();
                                }
                            } catch (Throwable ignored) { }
                        }
                    })
                    .setNeutralButton("Hapus Laporan", new DialogInterface.OnClickListener() {
                        @Override public void onClick(DialogInterface dialog, int which) {
                            try {
                                CrashReporter.deleteReport(activity.getApplicationContext());
                                View content = activity.findViewById(android.R.id.content);
                                if (content instanceof FrameLayout) {
                                    View entry = ((FrameLayout) content).findViewWithTag(TAG_CRASH_REPORT_BUTTON);
                                    if (entry != null) ((FrameLayout) content).removeView(entry);
                                }
                                Toast.makeText(activity, "Laporan dihapus", Toast.LENGTH_SHORT).show();
                            } catch (Throwable ignored) { }
                        }
                    })
                    .setNegativeButton("Tutup", null)
                    .show();
        } catch (Throwable ignored) { }
    }

    private static GradientDrawable buttonBackground() {
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xDD18345D);
        bg.setCornerRadius(12f);
        bg.setStroke(1, 0xFFFFD36A);
        return bg;
    }

    /** Shows the server-scheduled Cave Boss event state above the game UI.
     * This is an informational banner only; it does not create an enemy or start a battle. */
    public static void updateCaveBossStatus(final Activity activity, final JSONObject state) {
        if (activity == null || state == null || activity.isFinishing()) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    View content = activity.findViewById(android.R.id.content);
                    if (!(content instanceof FrameLayout)) return;
                    FrameLayout root = (FrameLayout) content;
                    TextView banner = (TextView) root.findViewWithTag(TAG_CAVE_BOSS_STATUS);
                    if (!state.optBoolean("active", false)) {
                        if (banner != null) banner.setVisibility(View.GONE);
                        return;
                    }
                    if (banner == null) {
                        banner = new TextView(activity);
                        banner.setTag(TAG_CAVE_BOSS_STATUS);
                        banner.setTextColor(Color.WHITE);
                        banner.setTextSize(11f);
                        banner.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                        banner.setPadding(dp(activity, 9), dp(activity, 6),
                                dp(activity, 9), dp(activity, 6));
                        banner.setBackgroundColor(0xDD17345F);
                        banner.setMaxWidth(dp(activity, 245));
                        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                                FrameLayout.LayoutParams.WRAP_CONTENT,
                                FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.RIGHT);
                        params.topMargin = dp(activity, 100);
                        params.rightMargin = dp(activity, 8);
                        root.addView(banner, params);
                    }
                    String name = state.optString("boss_name", "Boss Gua");
                    String difficulty = state.optString("difficulty", "normal");
                    String hp = state.optString("hp_multiplier", "1");
                    String minutes = state.optString("spawn_minutes", "");
                    banner.setText("JADWAL BOSS GUA AKTIF\n" + name + " • " + difficulty
                            + " • HP x" + hp + (minutes.length() > 0 ? " • " + minutes + " menit" : ""));
                    banner.setVisibility(View.VISIBLE);
                    banner.bringToFront();
                } catch (RuntimeException ignored) { }
            }
        });
    }

    /** Shows the Event Shop entry only while the server says the scheduled event is active. */
    public static void updateEventStoreStatus(final Activity activity, final JSONObject state) {
        if (activity == null || activity.isFinishing()) return;
        activity.runOnUiThread(new Runnable() {
            @Override public void run() {
                try {
                    View content = activity.findViewById(android.R.id.content);
                    if (!(content instanceof FrameLayout)) return;
                    View entry = ((FrameLayout) content).findViewWithTag(TAG_EVENT_STORE_BUTTON);
                    if (entry == null) return;
                    boolean active = state != null && state.optBoolean("active", false);
                    entry.setVisibility(active ? View.VISIBLE : View.GONE);
                    if (active) entry.bringToFront();
                } catch (RuntimeException ignored) { }
            }
        });
    }

    private static int dp(Activity activity, int value) {
        return (int) (value * activity.getResources().getDisplayMetrics().density + 0.5f);
    }
}
