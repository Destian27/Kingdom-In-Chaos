package com.destian.dtp;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

/** Game account entry overlay. It opens Supabase Google login before online account tools. */
public final class GameOnlineOverlay {
    private static final String TAG_ACCOUNT_BUTTON = "com.destian.dtp.GAME_ACCOUNT_BUTTON";
    private static final String TAG_CAVE_BOSS_STATUS = "com.destian.dtp.CAVE_BOSS_STATUS";
    private static final String TAG_EVENT_STORE_BUTTON = "com.destian.dtp.EVENT_STORE_BUTTON";
    private static final String TAG_CRASH_REPORT_BUTTON = "com.destian.dtp.CRASH_REPORT_BUTTON";

    private GameOnlineOverlay() { }

    public static void install(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        try {
            View content = activity.findViewById(android.R.id.content);
            if (!(content instanceof FrameLayout)) return;
            final FrameLayout root = (FrameLayout) content;

            Button accountButton = (Button) root.findViewWithTag(TAG_ACCOUNT_BUTTON);
            if (accountButton == null) {
                accountButton = new Button(activity);
                accountButton.setTag(TAG_ACCOUNT_BUTTON);
                accountButton.setTextSize(10f);
                accountButton.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                accountButton.setAllCaps(false);
                accountButton.setTextColor(Color.WHITE);
                accountButton.setPadding(dp(activity, 8), dp(activity, 3),
                        dp(activity, 8), dp(activity, 3));
                accountButton.setCompoundDrawablePadding(dp(activity, 5));
                accountButton.setBackground(buttonBackground());
                accountButton.setContentDescription("Login ke Kingdom In Chaos DTP");
                int iconId = activity.getResources().getIdentifier("icon", "drawable",
                        activity.getPackageName());
                if (iconId != 0) {
                    Drawable icon = activity.getResources().getDrawable(iconId).mutate();
                    icon.setBounds(0, 0, dp(activity, 24), dp(activity, 24));
                    accountButton.setCompoundDrawables(icon, null, null, null);
                }
                accountButton.setOnClickListener(new View.OnClickListener() {
                    @Override public void onClick(View view) {
                        try {
                            SupabaseGameBackend backend =
                                    new SupabaseGameBackend(activity.getApplicationContext());
                            Intent target = new Intent(activity, backend.hasSession()
                                    ? GameOnlineHubActivity.class : GameAuthActivity.class);
                            activity.startActivity(target);
                        } catch (RuntimeException ignored) { }
                    }
                });
                FrameLayout.LayoutParams accountParams = new FrameLayout.LayoutParams(
                        dp(activity, 104), dp(activity, 42), Gravity.TOP | Gravity.LEFT);
                accountParams.topMargin = dp(activity, 54);
                accountParams.leftMargin = dp(activity, 8);
                root.addView(accountButton, accountParams);
            }

            SupabaseGameBackend sessionBackend =
                    new SupabaseGameBackend(activity.getApplicationContext());
            accountButton.setText(sessionBackend.hasSession() ? "AKUN" : "LOGIN");
            accountButton.bringToFront();

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
            accountButton.bringToFront();
        } catch (Throwable ignored) {
            // The original native game keeps working if an optional overlay cannot be added.
        }
    }

    /** Tombol kecil yang hanya muncul jika sesi sebelumnya berakhir tidak wajar. */
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
            button.setText("LAPORAN CRASH");
            button.setTextSize(10f);
            button.setAllCaps(false);
            button.setTextColor(Color.WHITE);
            button.setBackground(buttonBackground());
            button.setContentDescription("Lihat laporan sesi game yang berakhir tidak wajar");
            button.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) {
                    showCrashReportDialog(activity);
                }
            });
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    dp(activity, 104), dp(activity, 36), Gravity.TOP | Gravity.LEFT);
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
            text.setTextSize(9f);
            text.setTypeface(Typeface.MONOSPACE);
            text.setTextIsSelectable(true);
            text.setPadding(dp(activity, 12), dp(activity, 8), dp(activity, 12), dp(activity, 8));
            scroll.addView(text);
            new AlertDialog.Builder(activity)
                    .setTitle("Laporan sesi tidak wajar")
                    .setView(scroll)
                    .setPositiveButton("Salin", new DialogInterface.OnClickListener() {
                        @Override public void onClick(DialogInterface dialog, int which) {
                            try {
                                ClipboardManager clipboard = (ClipboardManager)
                                        activity.getSystemService(Context.CLIPBOARD_SERVICE);
                                if (clipboard != null) {
                                    clipboard.setPrimaryClip(ClipData.newPlainText("Laporan KIC DTP", report));
                                    Toast.makeText(activity, "Laporan disalin", Toast.LENGTH_SHORT).show();
                                }
                            } catch (Throwable ignored) { }
                        }
                    })
                    .setNeutralButton("Hapus", new DialogInterface.OnClickListener() {
                        @Override public void onClick(DialogInterface dialog, int which) {
                            try {
                                CrashReporter.deleteReport(activity.getApplicationContext());
                                View content = activity.findViewById(android.R.id.content);
                                if (content instanceof FrameLayout) {
                                    View entry = ((FrameLayout) content).findViewWithTag(TAG_CRASH_REPORT_BUTTON);
                                    if (entry != null) ((FrameLayout) content).removeView(entry);
                                }
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
