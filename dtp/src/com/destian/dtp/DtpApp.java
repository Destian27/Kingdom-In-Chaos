package com.destian.dtp;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.view.WindowManager;
import android.content.SharedPreferences;
import org.json.JSONObject;

/**
 * Berjalan di proses game. Selama GameActivity tampil, cek status maintenance
 * tiap 2 detik. Begitu maintenance aktif, pemain langsung dikeluarkan ke layar
 * maintenance (proses game dimatikan lewat KickActivity supaya bersih).
 */
public class DtpApp extends Application implements Application.ActivityLifecycleCallbacks {

    private static final String GAME = "com.droidhang.ph.GameActivity";
    private static volatile DtpApp instance;
    private static final long POLL_MS = 2000;
    private static final long EVENT_STORE_POLL_MS = 1000L;
    // v17.14.17: jalur Google memanggil Edge Function, jadi dibatasi agar poll 1 detik Event Shop
    // tidak menjadi 1 request/detik ke server. Perubahan admin tetap terbaca dalam <= 10 detik.
    private static final long GOOGLE_ADMIN_MIN_INTERVAL_MS = 10000L;
    private volatile long googleCaveBossLastMs;
    private volatile long googleEventStoreLastMs;

    private final Handler h = new Handler(Looper.getMainLooper());
    private volatile Activity game;
    private volatile Activity foregroundActivity;
    private boolean busy;
    private boolean kicking;
    private boolean again;
    private RealtimeClient rt;
    private RealtimeClient playerStateRt;
    private RealtimeClient eventStoreRt;
    private RealtimeClient caveBossRt;
    private boolean runtimeRefreshBusy;
    private boolean runtimeRefreshAgain;
    private boolean caveBossRefreshBusy;
    private boolean eventStoreRefreshBusy;
    private boolean eventStoreRefreshAgain;

    private final Runnable caveBossPoll = new Runnable() {
        @Override public void run() {
            final Activity active = game;
            if (active == null || kicking) return;
            refreshCaveBossAsync(active);
            h.postDelayed(this, 15000L);
        }
    };

    private final Runnable eventStorePoll = new Runnable() {
        @Override public void run() {
            final Activity active = game;
            if (active == null || kicking) return;
            refreshEventStoreAsync(active);
            h.postDelayed(this, EVENT_STORE_POLL_MS);
        }
    };

    private int rewardPullTick;

    private final Runnable googleWalletSyncPoll = new Runnable() {
        @Override public void run() {
            final Activity active = game;
            if (active == null || kicking) return;
            if (foregroundActivity == active) {
                NativeGameRuntimeSync.syncGoogleWallet(active);
                // v17.14.20: hadiah admin masuk otomatis (sekitar tiap 20 detik) tanpa layar Surat.
                if ((++rewardPullTick % 2) == 0) NativeGameRuntimeSync.reconcileClaimedMail(active);
            }
            h.postDelayed(this, 10000L);
        }
    };

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            if (game == null || kicking) {
                return;
            }
            check(game);
            h.postDelayed(this, POLL_MS);
        }
    };

    public static DtpApp getInstance() {
        return instance;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        // v17.13: player login is direct Google Auth. Drop obsolete Supabase
        // player sessions/PKCE state so the old password/OAuth path cannot resume.
        getSharedPreferences("kic_supabase_session_v1", MODE_PRIVATE).edit().clear().apply();
        getSharedPreferences("kic_google_oauth_pending_v1", MODE_PRIVATE).edit().clear().apply();
        CrashReporter.onAppStart(this, new CrashReporter.ReportListener() {
            @Override public void onReportReady() {
                final Activity active = foregroundActivity;
                if (active != null && !active.isFinishing()) {
                    active.runOnUiThread(new Runnable() {
                        @Override public void run() {
                            GameOnlineOverlay.refreshCrashReportUi(active);
                        }
                    });
                }
            }
        });
        registerActivityLifecycleCallbacks(this);
    }

    private void check(final Activity a) {
        if (busy) {
            again = true;
            return;
        }
        busy = true;
        new Thread(new Runnable() {
            @Override
            public void run() {
                final MaintenanceActivity.Result r = MaintenanceActivity.fetchStatus();
                h.post(new Runnable() {
                    @Override
                    public void run() {
                        busy = false;
                        if (game != a || kicking) return;
                        // Gerbang awal (MaintenanceActivity) tetap ketat: tanpa status server valid game
                        // tidak dibuka. Saat game SUDAH berjalan, gangguan jaringan sesaat (mis. ketika
                        // menekan Start / loading berat) tidak boleh mengeluarkan pemain dari game.
                        // Pemain hanya dikeluarkan jika server secara eksplisit menyatakan maintenance.
                        if (!r.ok) {
                            a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
                            if (again) {
                                again = false;
                            }
                            return;
                        }
                        boolean under = r.active
                                && (r.startMs <= 0 || r.serverNow >= r.startMs)
                                && (r.endMs <= 0 || r.serverNow < r.endMs);
                        if (under) {
                            kick(a);
                        } else if (again) {
                            again = false;
                            check(a);
                        } else {
                            // Do not allow taps/gameplay until the server has validated the gate.
                            a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
                        }
                    }
                });
            }
        }).start();
    }

    private void kick(Activity a) {
        kicking = true;
        CrashReporter.clearMarker(this);
        h.removeCallbacks(poll);
        h.removeCallbacks(googleWalletSyncPoll);
        stopRt();
        stopPlayerStateRealtime();
        stopEventStoreRealtime();
        stopCaveBossRealtime();
        h.removeCallbacks(caveBossPoll);
        h.removeCallbacks(eventStorePoll);
        Intent target = new Intent(this, MaintenanceActivity.class);
        target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        Intent k = new Intent(this, KickActivity.class);
        k.putExtra("pid", Process.myPid());
        k.putExtra("target", target);
        a.startActivity(k);
    }

    @Override
    public void onActivityResumed(Activity a) {
        foregroundActivity = a;
        if (!GAME.equals(a.getClass().getName())) {
            // The launcher/maintenance screen is the first screen after relaunch. Show a
            // previous-session report here too, even before the player enters the game.
            if (a instanceof MaintenanceActivity) {
                GameOnlineOverlay.showPendingCrashReport(a);
            }
            return;
        }
        if (GAME.equals(a.getClass().getName())) {
            CrashReporter.mark(this, "game resumed; activity=" + a.getClass().getName()
                    + "; pid=" + android.os.Process.myPid());
            try {
                onGameResumed(a);
            } catch (Throwable error) {
                // Kode DTP (overlay/realtime) tidak boleh menjatuhkan game asli.
                CrashReporter.mark(this, "hook DTP gagal: " + error);
            }
        }
    }

    private void onGameResumed(Activity a) {
        if (GAME.equals(a.getClass().getName())) {
            // Fail closed immediately while the maintenance status is being verified.
            a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
            game = a;
            // Add a Java online entry point over the legacy game UI. The original
            // native online screens are not rewritten by this overlay.
            GameOnlineOverlay.install(a);
            NativeGameRuntimeSync.reconcileClaimedMail(a);
            h.removeCallbacks(poll);
            h.post(poll);
            h.removeCallbacks(googleWalletSyncPoll);
            h.postDelayed(googleWalletSyncPoll, 5000L);
            startRt();
            startPlayerStateRealtime(a);
            startEventStoreRealtime(a);
            startCaveBossRealtime(a);
            h.removeCallbacks(caveBossPoll);
            h.post(caveBossPoll);
            h.removeCallbacks(eventStorePoll);
            h.post(eventStorePoll);
        }
    }

    private void startRt() {
        stopRt();
        rt = new RealtimeClient(new RealtimeClient.Listener() {
            @Override
            public void onChange() {
                h.post(new Runnable() {
                    @Override
                    public void run() {
                        if (game != null && !kicking) {
                            check(game);
                        }
                    }
                });
            }
        });
        rt.start();
    }

    /**
     * Subscribe to the current player's rows changed by Admin (profile, cloud save,
     * economy). Wallet revisions are applied through the game's native wallet APIs
     * on the Cocos GL thread; other unsupported runtime stats remain backend-only.
     */
    private void startPlayerStateRealtime(final Activity activity) {
        stopPlayerStateRealtime();
        Thread boot = new Thread(new Runnable() {
            @Override public void run() {
                final SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                try {
                    if (!backend.hasSession()) return;
                    JSONObject user = backend.currentUser(); // validates/refreshes auth if required
                    final String uid = user.optString("id", "");
                    if (uid.length() == 0) return;
                    backend.getAccessTokenForRealtime();
                    cacheRuntimeSnapshot(backend.getMyRuntimeState());
                    cacheCaveBossState(backend.getActiveCaveBoss());
                    final RealtimeClient candidate = new RealtimeClient(new RealtimeClient.Listener() {
                        @Override public void onChange() { refreshRuntimeSnapshotAsync(); }
                    }, new String[] {"game_profiles", "game_player_saves", "game_admin_player_economy"},
                            "user_id=eq." + uid, backend, "realtime:player-state-" + uid);
                    h.post(new Runnable() {
                        @Override public void run() {
                            if (game == activity && !kicking) {
                                playerStateRt = candidate;
                                candidate.start();
                            } else {
                                candidate.stop();
                            }
                        }
                    });
                } catch (Throwable ignored) {
                    // Player Realtime is optional when no authenticated session exists.
                    // Maintenance is enforced separately and fails closed.
                }
            }
        }, "kic-player-state-bootstrap");
        boot.setDaemon(true);
        boot.start();
    }

    private void refreshRuntimeSnapshotAsync() {
        synchronized (this) {
            if (kicking) return;
            if (runtimeRefreshBusy) {
                runtimeRefreshAgain = true;
                return;
            }
            runtimeRefreshBusy = true;
            runtimeRefreshAgain = false;
        }
        Thread refresh = new Thread(new Runnable() {
            @Override public void run() {
                try {
                    SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                    cacheRuntimeSnapshot(backend.getMyRuntimeState());
                } catch (Throwable ignored) {
                    // A later Realtime event or resume retries the runtime snapshot.
                } finally {
                    boolean refreshAgain;
                    synchronized (DtpApp.this) {
                        runtimeRefreshBusy = false;
                        refreshAgain = runtimeRefreshAgain && !kicking;
                        runtimeRefreshAgain = false;
                    }
                    if (refreshAgain) refreshRuntimeSnapshotAsync();
                }
            }
        }, "kic-player-state-refresh");
        refresh.setDaemon(true);
        refresh.start();
    }

    private void cacheRuntimeSnapshot(JSONObject snapshot) {
        if (snapshot == null) return;
        SharedPreferences p = getSharedPreferences("kic_server_runtime_state", MODE_PRIVATE);
        p.edit().putString("runtime_snapshot_json", snapshot.toString())
                .putLong("received_at_ms", System.currentTimeMillis()).apply();
        // Coins, Crystals, Goblin Coins and Event Eyes are reconciled against the
        // original native wallet APIs on the Cocos GL thread. Other stats remain server-side.
        NativeGameRuntimeSync.apply(game, snapshot);
    }

    private void refreshCaveBossAsync(final Activity activity) {
        synchronized (this) {
            if (caveBossRefreshBusy || kicking || game != activity) return;
            caveBossRefreshBusy = true;
        }
        Thread refresh = new Thread(new Runnable() {
            @Override public void run() {
                try {
                    SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                    if (backend.hasSession()) {
                        cacheCaveBossState(backend.getActiveCaveBoss());
                    } else {
                        // v17.14.17: pemain login Google langsung tidak punya sesi Supabase -> baca lewat Edge Function.
                        // Tanpa ini perintah Boss Gua dari admin tidak pernah sampai ke game.
                        GooglePlayerBackend google = new GooglePlayerBackend(getApplicationContext());
                        long now = System.currentTimeMillis();
                        if (google.hasAccount() && now - googleCaveBossLastMs >= GOOGLE_ADMIN_MIN_INTERVAL_MS) {
                            googleCaveBossLastMs = now;
                            cacheCaveBossState(google.getCaveBoss());
                        }
                    }
                } catch (Throwable ignored) {
                    // Event status is informational; maintenance enforcement is separate.
                } finally {
                    synchronized (DtpApp.this) { caveBossRefreshBusy = false; }
                }
            }
        }, "kic-cave-boss-refresh");
        refresh.setDaemon(true);
        refresh.start();
    }

    private void cacheCaveBossState(final JSONObject state) {
        if (state == null) return;
        getSharedPreferences("kic_server_runtime_state", MODE_PRIVATE).edit()
                .putString("active_cave_boss_json", state.toString())
                .putLong("cave_boss_received_at_ms", System.currentTimeMillis()).apply();
        final Activity active = game;
        if (active != null && !kicking) {
            h.post(new Runnable() {
                @Override public void run() {
                    if (game == active && !kicking) GameOnlineOverlay.updateCaveBossStatus(active, state);
                }
            });
        }
    }

    private void refreshEventStoreAsync(final Activity activity) {
        synchronized (this) {
            if (kicking || game != activity) return;
            if (eventStoreRefreshBusy) {
                eventStoreRefreshAgain = true;
                return;
            }
            eventStoreRefreshBusy = true;
            eventStoreRefreshAgain = false;
        }
        Thread refresh = new Thread(new Runnable() {
            @Override public void run() {
                try {
                    SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                    if (backend.hasSession()) {
                        cacheEventStoreState(backend.getActiveEventStore());
                    } else {
                        // v17.14.17: sebelumnya di sini cache dikosongkan ({}) sehingga Event Shop dari admin
                        // tidak pernah tampil untuk pemain Google. Kini dibaca lewat Edge Function (dibatasi interval).
                        GooglePlayerBackend google = new GooglePlayerBackend(getApplicationContext());
                        long now = System.currentTimeMillis();
                        if (google.hasAccount()) {
                            if (now - googleEventStoreLastMs >= GOOGLE_ADMIN_MIN_INTERVAL_MS) {
                                googleEventStoreLastMs = now;
                                cacheEventStoreState(google.getEventStore());
                            }
                        } else {
                            cacheEventStoreState(new JSONObject());
                        }
                    }
                } catch (Throwable ignored) {
                    // Event shop is optional; do not block the original game on network failures.
                } finally {
                    boolean refreshAgain;
                    synchronized (DtpApp.this) {
                        eventStoreRefreshBusy = false;
                        refreshAgain = eventStoreRefreshAgain && !kicking && game == activity;
                        eventStoreRefreshAgain = false;
                    }
                    if (refreshAgain) refreshEventStoreAsync(activity);
                }
            }
        }, "kic-event-store-refresh");
        refresh.setDaemon(true);
        refresh.start();
    }

    private void cacheEventStoreState(final JSONObject state) {
        if (state == null) return;
        getSharedPreferences("kic_server_runtime_state", MODE_PRIVATE).edit()
                .putString("active_event_store_json", state.toString())
                .putLong("event_store_received_at_ms", System.currentTimeMillis()).apply();
        final Activity active = game;
        if (active != null && !kicking) {
            h.post(new Runnable() {
                @Override public void run() {
                    if (game == active && !kicking) GameOnlineOverlay.updateEventStoreStatus(active, state);
                }
            });
        }
    }

    /** Subscribe to the shared Event Shop configuration/catalogue without a user_id filter. */
    private void startEventStoreRealtime(final Activity activity) {
        stopEventStoreRealtime();
        Thread boot = new Thread(new Runnable() {
            @Override public void run() {
                final SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                try {
                    if (!backend.hasSession()) return;
                    backend.currentUser();
                    backend.getAccessTokenForRealtime();
                    final RealtimeClient candidate = new RealtimeClient(new RealtimeClient.Listener() {
                        @Override public void onChange() { refreshEventStoreAsync(activity); }
                    }, new String[] {"game_event_store_config", "game_event_store_items"}, null,
                            backend, "realtime:event-store");
                    h.post(new Runnable() {
                        @Override public void run() {
                            if (game == activity && !kicking) {
                                eventStoreRt = candidate;
                                candidate.start();
                            } else {
                                candidate.stop();
                            }
                        }
                    });
                } catch (Throwable ignored) {
                    // The one-second refresh remains as a fallback if Realtime cannot connect.
                }
            }
        }, "kic-event-store-realtime-bootstrap");
        boot.setDaemon(true);
        boot.start();
    }

    /** Subscribe to server-managed Cave Boss schedules and manual overrides. */
    private void startCaveBossRealtime(final Activity activity) {
        stopCaveBossRealtime();
        Thread boot = new Thread(new Runnable() {
            @Override public void run() {
                final SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                try {
                    if (!backend.hasSession()) return;
                    backend.currentUser();
                    backend.getAccessTokenForRealtime();
                    final RealtimeClient candidate = new RealtimeClient(new RealtimeClient.Listener() {
                        @Override public void onChange() { refreshCaveBossAsync(activity); }
                    }, new String[] {"game_cave_boss_hourly_schedule", "game_cave_boss_override"}, null,
                            backend, "realtime:cave-boss");
                    h.post(new Runnable() {
                        @Override public void run() {
                            if (game == activity && !kicking) {
                                caveBossRt = candidate;
                                candidate.start();
                            } else {
                                candidate.stop();
                            }
                        }
                    });
                } catch (Throwable ignored) {
                    // The existing periodic status refresh remains the fallback.
                }
            }
        }, "kic-cave-boss-realtime-bootstrap");
        boot.setDaemon(true);
        boot.start();
    }

    private void stopCaveBossRealtime() {
        if (caveBossRt != null) {
            caveBossRt.stop();
            caveBossRt = null;
        }
    }

    private void stopEventStoreRealtime() {
        if (eventStoreRt != null) {
            eventStoreRt.stop();
            eventStoreRt = null;
        }
    }

    private void stopPlayerStateRealtime() {
        if (playerStateRt != null) {
            playerStateRt.stop();
            playerStateRt = null;
        }
    }

    private void stopRt() {
        if (rt != null) {
            rt.stop();
            rt = null;
        }
    }

    @Override
    public void onActivityPaused(Activity a) {
        if (GAME.equals(a.getClass().getName())) {
            // A pause is not proof of a clean exit. Keep the marker so process death while
            // backgrounded is still diagnosed on the next launch.
            CrashReporter.mark(this, "game paused; changingConfigurations="
                    + a.isChangingConfigurations());
        }
        if (a == foregroundActivity) foregroundActivity = null;
        if (a == game) {
            game = null;
            h.removeCallbacks(poll);
            stopRt();
            stopPlayerStateRealtime();
            stopEventStoreRealtime();
            stopCaveBossRealtime();
            h.removeCallbacks(caveBossPoll);
            h.removeCallbacks(eventStorePoll);
        }
    }

    @Override public void onActivityCreated(Activity a, Bundle b) { }
    @Override public void onActivityStarted(Activity a) { }
    @Override public void onActivityStopped(Activity a) { }
    @Override public void onActivitySaveInstanceState(Activity a, Bundle b) { }
    @Override public void onActivityDestroyed(Activity a) {
        if (GAME.equals(a.getClass().getName()) && a.isFinishing()
                && !a.isChangingConfigurations()) {
            // Explicitly finishing the game is a normal exit, unlike an unexpected process death.
            CrashReporter.clearMarker(this);
        }
        if (a == foregroundActivity) foregroundActivity = null;
    }
}
