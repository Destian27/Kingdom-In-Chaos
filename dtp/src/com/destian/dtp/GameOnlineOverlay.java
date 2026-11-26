package com.destian.dtp;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.Color;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;

import org.json.JSONObject;

/** Adds a small entry point over the legacy native game without modifying libgame.so. */
public final class GameOnlineOverlay {
    private static final String TAG_ONLINE_BUTTON = "com.destian.dtp.GAME_ONLINE_BUTTON";
    private static final String TAG_CAVE_BOSS_STATUS = "com.destian.dtp.CAVE_BOSS_STATUS";
    private static final String TAG_EVENT_STORE_BUTTON = "com.destian.dtp.EVENT_STORE_BUTTON";

    private GameOnlineOverlay() { }

    public static void install(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        try {
            View content = activity.findViewById(android.R.id.content);
            if (!(content instanceof FrameLayout)) return;
            final FrameLayout root = (FrameLayout) content;
            if (root.findViewWithTag(TAG_ONLINE_BUTTON) != null) return;

            Button button = new Button(activity);
            button.setTag(TAG_ONLINE_BUTTON);
            button.setText("ONLINE");
            button.setTextSize(11f);
            button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            button.setAllCaps(false);
            button.setAlpha(0.94f);
            button.setContentDescription("Open Kingdom In Chaos online features");
            button.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View view) {
                    try {
                        Intent intent = new Intent(activity, GameOnlineHubActivity.class);
                        activity.startActivity(intent);
                    } catch (RuntimeException ignored) {
                        // Keep a UI integration failure from crashing the original game.
                    }
                }
            });

            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    dp(activity, 82), dp(activity, 42), Gravity.TOP | Gravity.RIGHT);
            params.topMargin = dp(activity, 8);
            params.rightMargin = dp(activity, 8);
            root.addView(button, params);
            button.bringToFront();

            Button eventButton = new Button(activity);
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
        } catch (RuntimeException ignored) {
            // Compatibility guard: never block the game if this overlay cannot be added.
        }
    }

    /** Shows the server-scheduled Cave Boss event state above the game UI. This is an
     * event banner only; it does not create an enemy or enter a Cave Boss battle scene. */
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
                        banner.setPadding(dp(activity, 9), dp(activity, 6), dp(activity, 9), dp(activity, 6));
                        banner.setBackgroundColor(0xDD17345F);
                        banner.setMaxWidth(dp(activity, 245));
                        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                                Gravity.TOP | Gravity.RIGHT);
                        params.topMargin = dp(activity, 100);
                        params.rightMargin = dp(activity, 8);
                        root.addView(banner, params);
                    }
                    String name = state.optString("boss_name", "Boss Gua");
                    String difficulty = state.optString("difficulty", "normal");
                    String hp = state.optString("hp_multiplier", "1");
                    String minutes = state.optString("spawn_minutes", "");
                    banner.setText("JADWAL BOSS GUA AKTIF\n" + name + " • " + difficulty + " • HP x" + hp
                            + (minutes.length() > 0 ? " • " + minutes + " menit" : ""));
                    banner.setVisibility(View.VISIBLE);
                    banner.bringToFront();
                } catch (RuntimeException ignored) {
                    // The legacy game must keep running if the informational banner fails.
                }
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
