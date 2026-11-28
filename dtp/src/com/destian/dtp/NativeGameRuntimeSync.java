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
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.json.JSONArray;

/** Applies only admin-revised wallet fields to the actual Cocos native runtime. */
final class NativeGameRuntimeSync {
    private static final String TAG = "KIC-NativeSync";
    private static final String PREFS = "kic_server_runtime_state";
    private static final int MAX_RETRIES = 8;
    private static final long START_GRACE_MS = 20000L;
    private static final long RETRY_MS = 5000L;
    private static final String MAIL_PENDING_PREFIX = "mail_reward_pending_";
    private static final String MAIL_APPLIED_PREFIX = "mail_reward_applied_";
    private static volatile boolean mailReconcileRunning;
    private static volatile boolean googleWalletSyncRunning;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private NativeGameRuntimeSync() { }

    /** Capture actual native values on Cocos GL thread and report a read-only snapshot to admin. */
    static void syncGoogleWallet(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        final GooglePlayerBackend backend = new GooglePlayerBackend(activity.getApplicationContext());
        if (!backend.hasAccount() || googleWalletSyncRunning) return;
        final GLSurfaceView gl = findGameSurface(activity);
        if (gl == null) return;
        googleWalletSyncRunning = true;
        try {
            gl.queueEvent(new Runnable() {
                @Override public void run() {
                    final Map<String, Integer> wallet = parseWallet(NativeGameRuntimeBridge.getWallet());
                    if (wallet == null) {
                        googleWalletSyncRunning = false;
                        return;
                    }
                    Thread upload = new Thread(new Runnable() {
                        @Override public void run() {
                            try {
                                backend.syncNativeWallet(wallet.get("coins"), wallet.get("dm"),
                                        wallet.get("goblin"), wallet.get("life"));
                            } catch (Exception error) {
                                Log.w(TAG, "Google native wallet sync deferred: " + error.getMessage());
                            } finally {
                                googleWalletSyncRunning = false;
                            }
                        }
                    }, "KIC-Google-Wallet-Upload");
                    upload.setDaemon(true);
                    upload.start();
                }
            });
        } catch (RuntimeException error) {
            googleWalletSyncRunning = false;
            Log.w(TAG, "Could not queue native wallet snapshot", error);
        }
    }

    /** Queue a claimed mail reward locally. No currency is modified here. */
    static boolean queueClaimedMail(Context context, JSONObject mail) {
        if (context == null || mail == null) return false;
        String mailId = mail.optString("mail_id", "").trim();
        if (!mailId.matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")) return false;
        JSONObject rewards = mail.optJSONObject("reward_config");
        if (rewards == null) {
            JSONObject claimResult = mail.optJSONObject("claim_result");
            rewards = claimResult == null ? null : claimResult.optJSONObject("rewards");
        }
        if (rewards == null) return false;
        int coins = safeReward(rewards, "coins");
        int crystals = safeReward(rewards, "crystals");
        int goblin = safeReward(rewards, "goblin_coins");
        int meat = safeReward(rewards, "meat");
        if (coins == 0 && crystals == 0 && goblin == 0 && meat == 0) return false;

        Context app = context.getApplicationContext();
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String pendingKey = MAIL_PENDING_PREFIX + mailId.toLowerCase(java.util.Locale.US);
        String appliedKey = MAIL_APPLIED_PREFIX + mailId.toLowerCase(java.util.Locale.US);
        if (prefs.contains(appliedKey) || prefs.contains(pendingKey)) return false;
        JSONObject record = new JSONObject();
        try {
            record.put("mail_id", mailId);
            record.put("created_at", mail.optString("created_at", ""));
            record.put("coins", coins);
            record.put("crystals", crystals);
            record.put("goblin_coins", goblin);
            record.put("meat", meat);
        } catch (Exception ignored) { return false; }
        return prefs.edit().putString(pendingKey, record.toString()).commit();
    }

    /**
     * v17.14.19: antrekan hadiah kode hadiah ke saldo native. Memakai jurnal yang sama dengan Surat;
     * claim_id (UUID dari server) menjadi kunci anti-ganda sehingga satu klaim hanya dikreditkan sekali.
     */
    static boolean queueCodeClaim(Context context, String claimId, JSONObject rewards) {
        if (context == null || rewards == null || claimId == null) return false;
        try {
            JSONObject pseudoMail = new JSONObject();
            pseudoMail.put("mail_id", claimId.trim());
            pseudoMail.put("created_at", "");
            pseudoMail.put("reward_config", rewards);
            return queueClaimedMail(context, pseudoMail);
        } catch (Exception ignored) { return false; }
    }

    private static int safeReward(JSONObject rewards, String key) {
        long value = rewards.optLong(key, 0L);
        if (value < 0L) return 0;
        return (int) Math.min(Integer.MAX_VALUE, value);
    }

    /**
     * Recover claimed letters after app restarts, then apply their wallet deltas
     * on the native Cocos GL thread. The journal stores absolute targets before
     * the native call, so partial retries do not duplicate a completed currency.
     */
    static void reconcileClaimedMail(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        final GooglePlayerBackend backend = new GooglePlayerBackend(activity.getApplicationContext());
        if (!backend.hasAccount() || mailReconcileRunning) {
            applyPendingMailRewards(activity);
            return;
        }
        mailReconcileRunning = true;
        Thread worker = new Thread(new Runnable() {
            @Override public void run() {
                try {
                    Context appCtx = activity.getApplicationContext();
                    boolean pulled = false;
                    try {
                        // v17.14.20: server mengklaim surat admin otomatis lalu mengembalikan semua klaim.
                        JSONObject pull = backend.pullRewards();
                        JSONArray claims = pull == null ? null : pull.optJSONArray("claims");
                        if (claims != null) {
                            for (int i = 0; i < claims.length(); i++) {
                                JSONObject claim = claims.optJSONObject(i);
                                if (claim == null) continue;
                                queueCodeClaim(appCtx, claim.optString("claim_id", ""), claim.optJSONObject("rewards"));
                            }
                        }
                        pulled = true;
                    } catch (Exception pullError) {
                        Log.w(TAG, "pull_rewards belum tersedia, memakai jalur lama: " + pullError.getMessage());
                    }
                    if (!pulled) {
                        // Cadangan bila Edge Function google-player lama masih terpasang.
                        JSONObject inbox = backend.getInbox();
                        JSONArray messages = inbox.optJSONArray("messages");
                        if (messages != null) {
                            for (int i = 0; i < messages.length(); i++) {
                                JSONObject mail = messages.optJSONObject(i);
                                if (mail == null) continue;
                                String claimedAt = mail.optString("claimed_at", "");
                                if (!claimedAt.isEmpty() && !"null".equals(claimedAt)) queueClaimedMail(appCtx, mail);
                            }
                        }
                        JSONObject claims = backend.getCodeClaims();
                        JSONArray list = claims == null ? null : claims.optJSONArray("claims");
                        if (list != null) {
                            for (int i = 0; i < list.length(); i++) {
                                JSONObject claim = list.optJSONObject(i);
                                if (claim == null) continue;
                                queueCodeClaim(appCtx, claim.optString("claim_id", ""), claim.optJSONObject("reward_applied"));
                            }
                        }
                    }
                } catch (Exception error) {
                    Log.w(TAG, "Mail recovery deferred: " + error.getMessage());
                } finally {
                    mailReconcileRunning = false;
                    MAIN.post(new Runnable() {
                        @Override public void run() { applyPendingMailRewards(activity); }
                    });
                }
            }
        }, "KIC-Mail-Reconcile");
        worker.setDaemon(true);
        worker.start();
    }

    static void applyPendingMailRewards(final Activity activity) {
        if (activity == null || activity.isFinishing()) return;
        MAIN.postDelayed(new Runnable() {
            @Override public void run() { attemptPendingMailRewards(activity, 0); }
        }, 700L);
    }

    private static void attemptPendingMailRewards(final Activity activity, final int retry) {
        if (activity == null || activity.isFinishing()) return;
        final SharedPreferences prefs = activity.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        final List<String> keys = pendingMailKeys(prefs);
        if (keys.isEmpty()) return;
        final GLSurfaceView gl = findGameSurface(activity);
        if (gl == null) {
            retryPending(activity, retry, "GL_SURFACE_NOT_READY");
            return;
        }
        try {
            gl.queueEvent(new Runnable() {
                @Override public void run() {
                    for (String key : keys) {
                        String raw = prefs.getString(key, null);
                        if (raw == null) continue;
                        try {
                            JSONObject record = new JSONObject(raw);
                            int targetCoins, targetCrystals, targetGoblin, targetLife;
                            if (record.has("target_coins")) {
                                targetCoins = record.getInt("target_coins");
                                targetCrystals = record.getInt("target_crystals");
                                targetGoblin = record.getInt("target_goblin");
                                targetLife = record.getInt("target_life");
                            } else {
                                String wallet = NativeGameRuntimeBridge.getWallet();
                                Map<String, Integer> current = parseWallet(wallet);
                                if (current == null) {
                                    prefs.edit().putString("native_mail_last_result", wallet).apply();
                                    break;
                                }
                                targetCoins = safeAdd(current.get("coins"), record.optInt("coins", 0));
                                targetCrystals = safeAdd(current.get("dm"), record.optInt("crystals", 0));
                                targetGoblin = safeAdd(current.get("goblin"), record.optInt("goblin_coins", 0));
                                targetLife = Math.min(current.get("life_max"), safeAdd(current.get("life"), record.optInt("meat", 0)));
                                record.put("target_coins", targetCoins);
                                record.put("target_crystals", targetCrystals);
                                record.put("target_goblin", targetGoblin);
                                record.put("target_life", targetLife);
                                // Persist the exact target before touching libgame.so.
                                if (!prefs.edit().putString(key, record.toString()).commit()) {
                                    prefs.edit().putString("native_mail_last_result", "MAIL_JOURNAL_WRITE_FAILED").apply();
                                    break;
                                }
                            }
                            String result = NativeGameRuntimeBridge.applyMailWalletTargets(
                                    targetCoins, targetCrystals, targetGoblin, targetLife);
                            prefs.edit().putString("native_mail_last_result", result).apply();
                            if (result != null && result.startsWith("OK|")) {
                                String id = record.optString("mail_id", "").toLowerCase(java.util.Locale.US);
                                prefs.edit().remove(key)
                                        .putString(MAIL_APPLIED_PREFIX + id, String.valueOf(System.currentTimeMillis()))
                                        .putLong("native_mail_applied_ms", System.currentTimeMillis()).commit();
                                Log.i(TAG, "Claimed mail rewards applied to native wallet: " + id + " " + result);
                            } else {
                                Log.w(TAG, "Mail reward native sync deferred: " + result);
                                break;
                            }
                        } catch (Exception error) {
                            prefs.edit().putString("native_mail_last_result", "MAIL_REWARD_ERROR:" + error.getMessage()).apply();
                            Log.e(TAG, "Could not apply pending mail reward", error);
                            break;
                        }
                    }
                    if (!pendingMailKeys(prefs).isEmpty()) {
                        MAIN.post(new Runnable() {
                            @Override public void run() { retryPending(activity, retry, "MAIL_REWARDS_PENDING"); }
                        });
                    }
                }
            });
        } catch (RuntimeException error) {
            retryPending(activity, retry, "GL_QUEUE_FAILED:" + error.getClass().getSimpleName());
        }
    }

    private static List<String> pendingMailKeys(SharedPreferences prefs) {
        List<String> keys = new ArrayList<>();
        for (Map.Entry<String, ?> entry : prefs.getAll().entrySet()) {
            if (entry.getKey().startsWith(MAIL_PENDING_PREFIX) && entry.getValue() instanceof String) keys.add(entry.getKey());
        }
        Collections.sort(keys, new Comparator<String>() {
            @Override public int compare(String left, String right) { return left.compareTo(right); }
        });
        return keys;
    }

    private static Map<String, Integer> parseWallet(String value) {
        if (value == null || !value.startsWith("coins=")) return null;
        java.util.HashMap<String, Integer> result = new java.util.HashMap<>();
        try {
            for (String part : value.split("[;|]")) {
                String[] pair = part.split("=", 2);
                if (pair.length == 2) result.put(pair[0].trim(), Integer.parseInt(pair[1].trim()));
            }
            if (!result.containsKey("coins") || !result.containsKey("dm") || !result.containsKey("goblin")
                    || !result.containsKey("life") || !result.containsKey("life_max")) return null;
            return result;
        } catch (Exception ignored) { return null; }
    }

    private static int safeAdd(int value, int delta) {
        long total = (long) value + Math.max(0, delta);
        return (int) Math.min(Integer.MAX_VALUE, total);
    }

    private static void retryPending(final Activity activity, int retry, String reason) {
        if (activity == null || activity.isFinishing()) return;
        activity.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString("native_mail_last_result", reason).apply();
        if (retry >= MAX_RETRIES) return;
        MAIN.postDelayed(new Runnable() {
            @Override public void run() { attemptPendingMailRewards(activity, retry + 1); }
        }, RETRY_MS);
    }

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
