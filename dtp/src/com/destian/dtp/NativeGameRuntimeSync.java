package com.destian.dtp;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.opengl.GLSurfaceView;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONObject;

import java.lang.reflect.Field;

/** Applies only admin-revised wallet fields to the actual Cocos native runtime. */
final class NativeGameRuntimeSync {
    private static final String TAG = "KIC-NativeSync";
    private static final String PREFS = "kic_server_runtime_state";
    private static final int MAX_RETRIES = 8;
    private static final long START_GRACE_MS = 20000L;
    private static final long RETRY_MS = 5000L;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private NativeGameRuntimeSync() { }

    static void apply(final Activity activity, final JSONObject snapshot) {
        if (activity == null || snapshot == null || activity.isFinishing()) return;
        final JSONObject economy = snapshot.optJSONObject("economy");
        if (economy == null || economy.length() == 0) return;

        final SharedPreferences prefs = activity.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        JSONObject profile = snapshot.optJSONObject("profile");
        String userId = profile == null ? "" : profile.optString("user_id", "");
        if (userId.length() == 0) return;
        final String coinsKey = "native_coins_revision_applied_" + userId;
        final String crystalsKey = "native_crystals_revision_applied_" + userId;
        final String goblinKey = "native_goblin_revision_applied_" + userId;
        final String eventEyesKey = "native_event_eyes_revision_applied_" + userId;
        final String coinsRevision = economy.optString("coins_admin_revision", "");
        final String crystalsRevision = economy.optString("crystals_admin_revision", "");
        final String goblinRevision = economy.optString("goblin_coins_admin_revision", "");
        final String eventEyesRevision = economy.optString("event_eyes_admin_revision", "");
        final long coins = newTarget(economy, "coins", coinsRevision, prefs, coinsKey);
        final long crystals = newTarget(economy, "crystals", crystalsRevision, prefs, crystalsKey);
        final long goblin = newTarget(economy, "goblin_coins", goblinRevision, prefs, goblinKey);
        final long eventEyes = newTarget(economy, "event_eyes", eventEyesRevision, prefs, eventEyesKey);
        if (coins < 0 && crystals < 0 && goblin < 0 && eventEyes < 0) return;

        // Beri waktu game selesai memuat (menu awal / tombol Start) sebelum menyentuh state native.
        MAIN.postDelayed(new Runnable() {
            @Override public void run() {
                attempt(activity, prefs, coinsRevision, crystalsRevision, goblinRevision, eventEyesRevision,
                        coinsKey, crystalsKey, goblinKey, eventEyesKey, coins, crystals, goblin, eventEyes, 0);
            }
        }, START_GRACE_MS);
    }

    private static long newTarget(JSONObject economy, String field, String revision,
                                  SharedPreferences prefs, String appliedKey) {
        if (revision == null || revision.length() == 0
                || revision.equals(prefs.getString(appliedKey, ""))) return -1L;
        long value = economy.optLong(field, -1L);
        return value >= 0L ? value : -1L;
    }

    private static void attempt(final Activity activity, final SharedPreferences prefs,
                                final String coinsRevision, final String crystalsRevision,
                                final String goblinRevision, final String eventEyesRevision,
                                final String coinsKey, final String crystalsKey, final String goblinKey,
                                final String eventEyesKey, final long coins, final long crystals,
                                final long goblin, final long eventEyes, final int retry) {
        if (activity.isFinishing()) return;
        final GLSurfaceView gl = findGameSurface(activity);
        if (gl == null) {
            retry(activity, prefs, coinsRevision, crystalsRevision, goblinRevision, eventEyesRevision,
                    coinsKey, crystalsKey, goblinKey, eventEyesKey, coins, crystals, goblin, eventEyes, retry, "GL_SURFACE_NOT_READY");
            return;
        }
        try {
            gl.queueEvent(new Runnable() {
                @Override public void run() {
                    String result = NativeGameRuntimeBridge.applyEconomy(coins, crystals, goblin, eventEyes);
                    prefs.edit().putString("native_economy_last_result", result).apply();
                    if (result != null && result.startsWith("OK|")) {
                        SharedPreferences.Editor edit = prefs.edit()
                                .putLong("native_economy_applied_ms", System.currentTimeMillis());
                        if (coins >= 0 && coinsRevision.length() > 0)
                            edit.putString(coinsKey, coinsRevision);
                        if (crystals >= 0 && crystalsRevision.length() > 0)
                            edit.putString(crystalsKey, crystalsRevision);
                        if (goblin >= 0 && goblinRevision.length() > 0)
                            edit.putString(goblinKey, goblinRevision);
                        if (eventEyes >= 0 && eventEyesRevision.length() > 0)
                            edit.putString(eventEyesKey, eventEyesRevision);
                        edit.apply();
                        Log.i(TAG, "Admin wallet revision applied to native game: " + result);
                    } else {
                        Log.w(TAG, "Native wallet sync not applied: " + result);
                        if ("GAME_STATE_NOT_READY".equals(result) || "GAME_LIBRARY_NOT_LOADED".equals(result)
                                || "USER_DATA_MANAGER_NOT_READY".equals(result)) {
                            retry(activity, prefs, coinsRevision, crystalsRevision, goblinRevision, eventEyesRevision,
                                    coinsKey, crystalsKey, goblinKey, eventEyesKey, coins, crystals, goblin, eventEyes, retry, result);
                        }
                    }
                }
            });
        } catch (RuntimeException error) {
            retry(activity, prefs, coinsRevision, crystalsRevision, goblinRevision, eventEyesRevision,
                    coinsKey, crystalsKey, goblinKey, eventEyesKey, coins, crystals, goblin, eventEyes, retry, "GL_QUEUE_FAILED:" + error.getClass().getSimpleName());
        }
    }

    private static void retry(final Activity activity, final SharedPreferences prefs,
                              final String coinsRevision, final String crystalsRevision,
                              final String goblinRevision, final String eventEyesRevision,
                              final String coinsKey, final String crystalsKey, final String goblinKey,
                              final String eventEyesKey, final long coins, final long crystals,
                              final long goblin, final long eventEyes, final int retry, String reason) {
        prefs.edit().putString("native_economy_last_result", reason).apply();
        if (retry >= MAX_RETRIES || activity.isFinishing()) return;
        MAIN.postDelayed(new Runnable() {
            @Override public void run() {
                attempt(activity, prefs, coinsRevision, crystalsRevision, goblinRevision, eventEyesRevision,
                        coinsKey, crystalsKey, goblinKey, eventEyesKey, coins, crystals, goblin, eventEyes, retry + 1);
            }
        }, RETRY_MS);
    }

    private static GLSurfaceView findGameSurface(Activity activity) {
        Class<?> type = activity.getClass();
        while (type != null) {
            try {
                Field field = type.getDeclaredField("mGLSurfaceView");
                field.setAccessible(true);
                Object value = field.get(activity);
                return value instanceof GLSurfaceView ? (GLSurfaceView) value : null;
            } catch (NoSuchFieldException ignored) {
                type = type.getSuperclass();
            } catch (Exception error) {
                Log.w(TAG, "Could not access Cocos GL surface", error);
                return null;
            }
        }
        return null;
    }
}
