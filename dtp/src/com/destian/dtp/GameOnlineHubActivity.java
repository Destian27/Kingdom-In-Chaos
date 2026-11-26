package com.destian.dtp;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * A Java online hub accessible from the DTP in-game ONLINE button. It uses the
 * Supabase adapter, but does not replace or claim to restore native C++ gameplay.
 */
public final class GameOnlineHubActivity extends Activity {
    private SupabaseGameBackend backend;
    private ExecutorService executor;
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextView output;
    private RealtimeClient runtimeRealtime;
    private boolean runtimeRealtimeStarting;

    private EditText email;
    private EditText password;
    private EditText username;
    private EditText nickname;
    private EditText avatarId;
    private EditText region;
    private EditText playerQuery;
    private EditText targetUserId;
    private EditText friendRequestId;
    private EditText cycleId;
    private EditText bossScore;
    private EditText roomCode;
    private EditText pvpMatchId;

    private interface BackendTask { String execute() throws Exception; }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("Kingdom In Chaos — Online");
        backend = new SupabaseGameBackend(this);
        executor = Executors.newSingleThreadExecutor();
        buildUi();
        output.setText(backend.hasSession()
                ? "Sesi Supabase tersimpan. Realtime akan memuat perubahan Admin pada profil, cloud save, dan ekonomi."
                : "Belum login. Login/daftar dulu untuk memakai fitur online.");
        if (backend.hasSession()) ensureRuntimeRealtimeSubscription();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(14);
        page.setPadding(pad, pad, pad, pad);
        scroll.setFillViewport(true);
        scroll.addView(page, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(scroll);

        TextView title = new TextView(this);
        title.setText("KINGDOM IN CHAOS DTP • ONLINE HUB");
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        page.addView(title, matchWrap());
        TextView note = new TextView(this);
        note.setText("Login, profil/avatar, teman, ranking, antrean PvP, dan World Boss. Realtime memperbarui snapshot server. Coins, Crystals, dan Goblin Coins yang diubah admin diterapkan ke wallet native game melalui JNI; PvP/World Boss dan statistik lain belum menjalankan gameplay native.");
        note.setTextSize(13);
        page.addView(note, matchWrap());

        heading(page, "1. Akun");
        email = addInput(page, "Email", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        password = addInput(page, "Password", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        username = addInput(page, "Username (untuk daftar)", InputType.TYPE_CLASS_TEXT);
        nickname = addInput(page, "Nickname", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Daftar", new Runnable() { @Override public void run() {
            final String vEmail = value(email), vPassword = value(password), vUsername = value(username), vNickname = value(nickname);
            runBackend("Daftar", new BackendTask() { @Override public String execute() throws Exception {
                return backend.signUp(vEmail, vPassword, vUsername, vNickname).toString();
            }});
        }});
        addButton(page, "Login", new Runnable() { @Override public void run() {
            final String vEmail = value(email), vPassword = value(password);
            runBackend("Login", new BackendTask() { @Override public String execute() throws Exception {
                return backend.signInWithPassword(vEmail, vPassword).toString();
            }});
        }});
        addButton(page, "Muat Profil", new Runnable() { @Override public void run() {
            runBackend("Profil", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getMyProfile().toString();
            }});
        }});
        addButton(page, "Muat Snapshot Real-time (Coins / XP / Save)", new Runnable() { @Override public void run() {
            runBackend("Snapshot server terbaru", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getMyRuntimeState().toString();
            }});
        }});
        avatarId = addInput(page, "Avatar ID (ID aset avatar lama)", InputType.TYPE_CLASS_NUMBER);
        region = addInput(page, "Region (contoh: ID)", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Simpan Nickname / Avatar / Region", new Runnable() { @Override public void run() {
            final String vNickname = value(nickname), vAvatar = value(avatarId), vRegion = value(region);
            runBackend("Perbarui profil", new BackendTask() { @Override public String execute() throws Exception {
                int id = Integer.parseInt(vAvatar);
                return backend.updateProfile(vNickname, id, vRegion).toString();
            }});
        }});
        addButton(page, "Logout", new Runnable() { @Override public void run() {
            runBackend("Logout", new BackendTask() { @Override public String execute() throws Exception {
                backend.signOut(); return "Logout berhasil; token lokal dihapus.";
            }});
        }});

        heading(page, "2. Teman");
        playerQuery = addInput(page, "Cari username/nickname (min. 2 karakter)", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Cari Pemain", new Runnable() { @Override public void run() {
            final String query = value(playerQuery);
            runBackend("Hasil pencarian pemain", new BackendTask() { @Override public String execute() throws Exception {
                return backend.findPlayers(query, 25).toString();
            }});
        }});
        targetUserId = addInput(page, "UUID user tujuan", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Kirim Permintaan Teman", new Runnable() { @Override public void run() {
            final String id = value(targetUserId);
            runBackend("Permintaan teman", new BackendTask() { @Override public String execute() throws Exception {
                return backend.sendFriendRequest(id).toString();
            }});
        }});
        addButton(page, "Muat Teman", new Runnable() { @Override public void run() {
            runBackend("Daftar teman", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getFriends().toString();
            }});
        }});
        addButton(page, "Muat Permintaan Teman", new Runnable() { @Override public void run() {
            runBackend("Permintaan masuk", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getFriendRequests().toString();
            }});
        }});
        friendRequestId = addInput(page, "ID permintaan teman (lihat hasil di bawah)", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Terima Permintaan", new Runnable() { @Override public void run() {
            friendResponse(true);
        }});
        addButton(page, "Tolak Permintaan", new Runnable() { @Override public void run() {
            friendResponse(false);
        }});

        heading(page, "3. Ranking dan kehadiran");
        addButton(page, "Muat Ranking", new Runnable() { @Override public void run() {
            runBackend("Ranking", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getRankings(100).toString();
            }});
        }});
        roomCode = addInput(page, "Room code (boleh kosong)", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Heartbeat / Online", new Runnable() { @Override public void run() {
            final String room = value(roomCode);
            runBackend("Status online", new BackendTask() { @Override public String execute() throws Exception {
                return backend.heartbeat(room).toString();
            }});
        }});
        addButton(page, "Tandai Offline", new Runnable() { @Override public void run() {
            runBackend("Status offline", new BackendTask() { @Override public String execute() throws Exception {
                return backend.markOffline().toString();
            }});
        }});

        heading(page, "4. PvP (antrean/state server; belum menjalankan battle native)");
        addButton(page, "Masuk / Periksa Antrean PvP", new Runnable() { @Override public void run() {
            runBackend("Antrean PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.joinPvpQueue().toString();
            }});
        }});
        addButton(page, "Batalkan Antrean PvP", new Runnable() { @Override public void run() {
            runBackend("Batalkan PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.cancelPvpQueue().toString();
            }});
        }});
        addButton(page, "Riwayat PvP", new Runnable() { @Override public void run() {
            runBackend("Riwayat PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getPvpHistory(50).toString();
            }});
        }});
        pvpMatchId = addInput(page, "Match UUID (salin dari hasil antrean)", InputType.TYPE_CLASS_TEXT);
        addButton(page, "Periksa Status Match PvP", new Runnable() { @Override public void run() {
            final String id = value(pvpMatchId);
            runBackend("Status match PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getPvpMatchState(id).toString();
            }});
        }});

        heading(page, "5. World Boss (skor menunggu verifikasi)");
        addButton(page, "Muat Siklus World Boss Aktif", new Runnable() { @Override public void run() {
            runBackend("Siklus World Boss", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getActiveWorldBossCycles().toString();
            }});
        }});
        cycleId = addInput(page, "Cycle ID (salin dari hasil siklus)", InputType.TYPE_CLASS_TEXT);
        bossScore = addInput(page, "Skor yang diajukan", InputType.TYPE_CLASS_NUMBER);
        addButton(page, "Ranking World Boss", new Runnable() { @Override public void run() {
            final String cycle = value(cycleId);
            runBackend("Ranking World Boss", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getWorldBossRankings(cycle, 100).toString();
            }});
        }});
        addButton(page, "Ajukan Skor World Boss", new Runnable() { @Override public void run() {
            final String cycle = value(cycleId), score = value(bossScore);
            runBackend("Pengajuan skor World Boss", new BackendTask() { @Override public String execute() throws Exception {
                long number = Long.parseLong(score);
                return backend.submitWorldBossScoreClaim(cycle, number, new JSONObject()).toString();
            }});
        }});
        addButton(page, "Lihat Pengajuan Skor Saya", new Runnable() { @Override public void run() {
            final String cycle = value(cycleId);
            runBackend("Pengajuan skor saya", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getMyWorldBossClaims(cycle).toString();
            }});
        }});

        heading(page, "Hasil / pesan dari server");
        output = new TextView(this);
        output.setTextIsSelectable(true);
        output.setTextSize(12);
        output.setPadding(dp(10), dp(10), dp(10), dp(10));
        output.setBackgroundColor(0xFFEFEFEF);
        page.addView(output, matchWrap());
        addButton(page, "Kembali ke Game", new Runnable() { @Override public void run() { finish(); }});
    }

    private void ensureRuntimeRealtimeSubscription() {
        if (isFinishing() || backend == null) return;
        if (!backend.hasSession()) {
            stopRuntimeRealtimeSubscription();
            return;
        }
        if (runtimeRealtime != null || runtimeRealtimeStarting || executor == null || executor.isShutdown()) return;
        runtimeRealtimeStarting = true;
        executor.execute(new Runnable() {
            @Override public void run() {
                try {
                    JSONObject user = backend.currentUser();
                    final String uid = user.optString("id", "");
                    if (uid.length() == 0) throw new IllegalStateException("Supabase user ID is missing");
                    backend.getAccessTokenForRealtime();
                    final RealtimeClient candidate = new RealtimeClient(new RealtimeClient.Listener() {
                        @Override public void onChange() {
                            if (executor != null && !executor.isShutdown()) {
                                executor.execute(new Runnable() {
                                    @Override public void run() {
                                        try {
                                            final String state = backend.getMyRuntimeState().toString();
                                            main.post(new Runnable() {
                                                @Override public void run() {
                                                    if (!isFinishing() && output != null) {
                                                        output.setText("Realtime: data admin diperbarui\n" + state);
                                                    }
                                                }
                                            });
                                        } catch (final Exception e) {
                                            main.post(new Runnable() {
                                                @Override public void run() {
                                                    if (!isFinishing() && output != null)
                                                        output.setText("Realtime menerima perubahan, tetapi snapshot gagal: " + e.getMessage());
                                                }
                                            });
                                        }
                                    }
                                });
                            }
                        }
                    }, new String[] {"game_profiles", "game_player_saves", "game_admin_player_economy"},
                            "user_id=eq." + uid, backend);
                    main.post(new Runnable() {
                        @Override public void run() {
                            runtimeRealtimeStarting = false;
                            if (isFinishing() || !backend.hasSession()) candidate.stop();
                            else { runtimeRealtime = candidate; candidate.start(); }
                        }
                    });
                } catch (Exception e) {
                    main.post(new Runnable() {
                        @Override public void run() { runtimeRealtimeStarting = false; }
                    });
                }
            }
        });
    }

    private void stopRuntimeRealtimeSubscription() {
        if (runtimeRealtime != null) {
            runtimeRealtime.stop();
            runtimeRealtime = null;
        }
        runtimeRealtimeStarting = false;
    }

    private void friendResponse(final boolean accept) {
        final String id = value(friendRequestId);
        runBackend(accept ? "Terima teman" : "Tolak teman", new BackendTask() {
            @Override public String execute() throws Exception {
                return backend.respondFriendRequest(id, accept).toString();
            }
        });
    }

    private void runBackend(final String label, final BackendTask task) {
        output.setText(label + ": sedang menghubungi Supabase...");
        if (executor == null || executor.isShutdown()) {
            output.setText("Activity sudah ditutup. Buka ulang Online Hub.");
            return;
        }
        executor.execute(new Runnable() {
            @Override public void run() {
                try {
                    final String result = task.execute();
                    main.post(new Runnable() {
                        @Override public void run() {
                            if (!isFinishing() && output != null) {
                                output.setText(label + "\n" + result);
                                ensureRuntimeRealtimeSubscription();
                            }
                        }
                    });
                } catch (final Exception e) {
                    main.post(new Runnable() {
                        @Override public void run() {
                            if (!isFinishing() && output != null) {
                                output.setText(label + " gagal\n" + e.getMessage()
                                        + "\nPeriksa koneksi, SQL migration, aturan Auth, dan izin Supabase.");
                            }
                        }
                    });
                }
            }
        });
    }

    private EditText addInput(LinearLayout parent, String hint, int type) {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint(hint);
        input.setInputType(type);
        input.setTextSize(14);
        parent.addView(input, matchWrap());
        return input;
    }

    private void heading(LinearLayout parent, String text) {
        TextView label = new TextView(this);
        label.setText(text);
        label.setTextSize(17);
        label.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        label.setPadding(0, dp(14), 0, dp(4));
        parent.addView(label, matchWrap());
    }

    private void addButton(LinearLayout parent, String text, final Runnable action) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        button.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { action.run(); }
        });
        LinearLayout.LayoutParams params = matchWrap();
        params.topMargin = dp(3);
        params.bottomMargin = dp(3);
        parent.addView(button, params);
    }

    private static LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static String value(EditText input) {
        return input == null || input.getText() == null ? "" : input.getText().toString().trim();
    }

    @Override
    protected void onDestroy() {
        stopRuntimeRealtimeSubscription();
        if (executor != null) executor.shutdownNow();
        super.onDestroy();
    }
}
