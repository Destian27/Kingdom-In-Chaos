package com.destian.dtp;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.widget.Toast;

import java.util.Map;

/**
 * v1.0.8: Ganti Akun dan Keluar dari akun untuk dialog Masuk/Daftar bawaan game.
 *
 * Game menyimpan akun yang sedang masuk di CCUserDefault (SharedPreferences "Cocos2dxPrefsFile") dengan enam
 * kunci milik NetworkManager::getKey(AccountPersistenceType 0..5). Keluar = hapus token sesi DTP + enam kunci itu,
 * lalu proses game dimulai ulang agar status akun di memori native ikut bersih.
 */
public final class AccountSession {
    static final String NATIVE_PREFS = "Cocos2dxPrefsFile";
    static final String[] NATIVE_ACCOUNT_KEYS = {
            "vsrrcvgl", "swapdrtg", "dwnxgldd", "ptmqpswf", "sjowkfzn", "hloomrqb"};
    private static final String UI_PREFS = "kic_account_ui_v1";
    private static final String KEY_HINT = "hint";

    private AccountSession() { }

    /** True bila game sendiri mencatat akun yang masuk (salah satu kunci akun berisi nilai). */
    public static boolean nativeAccountPresent(Context context) {
        try {
            SharedPreferences prefs = context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE);
            Map<String, ?> all = prefs.getAll();
            for (String key : NATIVE_ACCOUNT_KEYS) {
                Object value = all.get(key);
                if (value instanceof String && !((String) value).isEmpty()) return true;
                if (value instanceof Integer && ((Integer) value) != 0) return true;
                if (value instanceof Long && ((Long) value) != 0L) return true;
            }
        } catch (RuntimeException ignored) { }
        return false;
    }

    public static boolean hasAnyAccount(Context context) {
        try {
            if (new PlayerBackend(context.getApplicationContext()).hasAccount()) return true;
        } catch (RuntimeException ignored) { }
        return nativeAccountPresent(context);
    }

    /** Hapus akun dari perangkat (sinkron/commit, aman sebelum proses dimatikan). */
    static void clearEverythingNow(Context context, boolean switchAccount) {
        Context app = context.getApplicationContext();
        new PlayerBackend(app).clearAccountNow();
        LocalAuthServer.forgetVerifiedPassword();
        SharedPreferences.Editor nativePrefs = app.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE).edit();
        for (String key : NATIVE_ACCOUNT_KEYS) nativePrefs.remove(key);
        nativePrefs.commit();
        SharedPreferences.Editor ui = app.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE).edit();
        if (switchAccount) ui.putString(KEY_HINT, "switch"); else ui.remove(KEY_HINT);
        ui.commit();
    }

    /** Tampilkan petunjuk sekali setelah Ganti Akun (dipanggil saat game terbuka lagi). */
    public static void showPendingHint(Activity activity) {
        try {
            SharedPreferences ui = activity.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE);
            if (!"switch".equals(ui.getString(KEY_HINT, ""))) return;
            ui.edit().remove(KEY_HINT).apply();
            Toast.makeText(activity, "Ketuk kotak avatar di kiri bawah untuk Masuk dengan akun lain.", Toast.LENGTH_LONG).show();
        } catch (RuntimeException ignored) { }
    }

    /** Keluar (switchAccount=false) atau Ganti Akun (true): bersihkan akun lalu mulai ulang game. */
    public static void signOutAndRestart(final Activity activity, final boolean switchAccount) {
        if (activity == null) return;
        final Context app = activity.getApplicationContext();
        Toast.makeText(activity, switchAccount ? "Mengganti akun... game dimulai ulang." : "Keluar dari akun... game dimulai ulang.",
                Toast.LENGTH_SHORT).show();
        Thread worker = new Thread(new Runnable() {
            @Override public void run() {
                try { clearEverythingNow(app, switchAccount); } catch (RuntimeException ignored) { }
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override public void run() { restartProcess(activity, app); }
                });
            }
        }, "kic-sign-out");
        worker.setDaemon(true);
        worker.start();
    }

    private static void restartProcess(Activity activity, Context app) {
        try {
            Intent launch = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
                PendingIntent pending = PendingIntent.getActivity(app, 7391, launch,
                        PendingIntent.FLAG_CANCEL_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                AlarmManager alarms = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
                if (alarms != null) alarms.set(AlarmManager.RTC, System.currentTimeMillis() + 700L, pending);
            }
            activity.finishAffinity();
        } catch (RuntimeException ignored) { }
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override public void run() {
                Process.killProcess(Process.myPid());
                System.exit(0);
            }
        }, 250L);
    }
}
