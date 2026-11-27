package com.destian.dtp;

import android.app.Activity;
import android.content.Intent;
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
 * A Java online hub for direct Google player identity and DTP account utilities.
 * Legacy Supabase Auth gameplay modules remain hidden and are not presented as active.
 */
public final class GameOnlineHubActivity extends Activity {
    private SupabaseGameBackend backend;
    private ExecutorService executor;
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextView output;
    private RealtimeClient runtimeRealtime;
    private boolean runtimeRealtimeStarting;

    private GooglePlayerBackend googleBackend;
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
        googleBackend = new GooglePlayerBackend(this);
        executor = Executors.newSingleThreadExecutor();
        buildUi();
        output.setText(googleBackend.hasAccount()
                ? "Akun Google tersambung. Database game menyimpan profil dan saldo pemain; Supabase Auth tidak digunakan untuk login pemain."
                : "Belum login. Gunakan akun Google untuk membuat profil pemain.");
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
        note.setText("Akun pemain memakai Google langsung. Gunakan Surat untuk hadiah admin, Kode Hadiah untuk kode promo, dan Daging untuk energi misi. Dashboard admin hanya memantau profil Google serta snapshot wallet native; admin tidak mengedit saldo atau profil pemain secara langsung. Data realtime memerlukan koneksi internet.");
        note.setTextSize(13);
        page.addView(note, matchWrap());

        heading(page, "Akun Google");
        addButton(page, "Lanjutkan dengan Google", new Runnable() {
            @Override public void run() {
                startActivity(new Intent(GameOnlineHubActivity.this, GameAuthActivity.class));
            }
        });
        addButton(page, "Lihat Profil, ID Pemain, dan Saldo", new Runnable() {
            @Override public void run() {
                runGoogleBackend("Profil dan saldo Google", "get_state", new JSONObject());
            }
        });
        addButton(page, "Kode Hadiah", new Runnable() {
            @Override public void run() {
                startActivity(new Intent(GameOnlineHubActivity.this, GameGiftCodeActivity.class));
            }
        });
        addButton(page, "Surat / Kotak Surat", new Runnable() {
            @Override public void run() {
                if (!googleBackend.hasAccount()) {
                    startActivity(new Intent(GameOnlineHubActivity.this, GameAuthActivity.class));
                } else {
                    startActivity(new Intent(GameOnlineHubActivity.this, GameMailActivity.class));
                }
            }
        });
        addButton(page, "Daging / Energi Misi", new Runnable() {
            @Override public void run() {
                startActivity(new Intent(GameOnlineHubActivity.this, GameMeatActivity.class));
            }
        });
        addButton(page, "Logout Google", new Runnable() {
            @Override public void run() {
                googleBackend.clearAccount();
                output.setText("Akun Google dilepas dari perangkat ini.");
            }
        });
        TextView authHint = new TextView(this);
        authHint.setText("Login pemain hanya memakai Google. Tidak ada password atau konfirmasi password game. Email harus terverifikasi oleh Google. Foto profil Google disegarkan saat sinkronisasi akun; avatar karakter native game tetap mengikuti data game lokal.");
        authHint.setTextSize(12);
        page.addView(authHint, matchWrap());

        LinearLayout legacyGroup = new LinearLayout(this);
        legacyGroup.setOrientation(LinearLayout.VERTICAL);
        legacyGroup.setVisibility(View.GONE); // Old modules still require Supabase Auth and are intentionally hidden.
        page.addView(legacyGroup, matchWrap());
        heading(legacyGroup, "Fitur akun online lama");
        TextView legacyHint = new TextView(this);
        legacyHint.setText("Teman, PvP, ranking, dan beberapa snapshot lama masih memakai integrasi Supabase Auth versi sebelumnya. Modul tersebut belum otomatis berpindah ke identitas Google langsung.");
        legacyHint.setTextSize(12);
        legacyGroup.addView(legacyHint, matchWrap());

        heading(legacyGroup, "2. Teman");
        playerQuery = addInput(legacyGroup, "Cari username/nickname (min. 2 karakter)", InputType.TYPE_CLASS_TEXT);
        addButton(legacyGroup, "Cari Pemain", new Runnable() { @Override public void run() {
            final String query = value(playerQuery);
            runBackend("Hasil pencarian pemain", new BackendTask() { @Override public String execute() throws Exception {
                return backend.findPlayers(query, 25).toString();
            }});
        }});
        targetUserId = addInput(legacyGroup, "UUID user tujuan", InputType.TYPE_CLASS_TEXT);
        addButton(legacyGroup, "Kirim Permintaan Teman", new Runnable() { @Override public void run() {
            final String id = value(targetUserId);
            runBackend("Permintaan teman", new BackendTask() { @Override public String execute() throws Exception {
                return backend.sendFriendRequest(id).toString();
            }});
        }});
        addButton(legacyGroup, "Muat Teman", new Runnable() { @Override public void run() {
            runBackend("Daftar teman", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getFriends().toString();
            }});
        }});
        addButton(legacyGroup, "Muat Permintaan Teman", new Runnable() { @Override public void run() {
            runBackend("Permintaan masuk", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getFriendRequests().toString();
            }});
        }});
        friendRequestId = addInput(legacyGroup, "ID permintaan teman (lihat hasil di bawah)", InputType.TYPE_CLASS_TEXT);
        addButton(legacyGroup, "Terima Permintaan", new Runnable() { @Override public void run() {
            friendResponse(true);
        }});
        addButton(legacyGroup, "Tolak Permintaan", new Runnable() { @Override public void run() {
            friendResponse(false);
        }});

        heading(legacyGroup, "3. Ranking dan kehadiran");
        addButton(legacyGroup, "Muat Ranking", new Runnable() { @Override public void run() {
            runBackend("Ranking", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getRankings(100).toString();
            }});
        }});
        roomCode = addInput(legacyGroup, "Room code (boleh kosong)", InputType.TYPE_CLASS_TEXT);
        addButton(legacyGroup, "Heartbeat / Online", new Runnable() { @Override public void run() {
            final String room = value(roomCode);
            runBackend("Status online", new BackendTask() { @Override public String execute() throws Exception {
                return backend.heartbeat(room).toString();
            }});
        }});
        addButton(legacyGroup, "Tandai Offline", new Runnable() { @Override public void run() {
            runBackend("Status offline", new BackendTask() { @Override public String execute() throws Exception {
                return backend.markOffline().toString();
            }});
        }});

        heading(legacyGroup, "4. PvP (antrean/state server; belum menjalankan battle native)");
        addButton(legacyGroup, "Masuk / Periksa Antrean PvP", new Runnable() { @Override public void run() {
            runBackend("Antrean PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.joinPvpQueue().toString();
            }});
        }});
        addButton(legacyGroup, "Batalkan Antrean PvP", new Runnable() { @Override public void run() {
            runBackend("Batalkan PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.cancelPvpQueue().toString();
            }});
        }});
        addButton(legacyGroup, "Riwayat PvP", new Runnable() { @Override public void run() {
            runBackend("Riwayat PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getPvpHistory(50).toString();
            }});
        }});
        pvpMatchId = addInput(legacyGroup, "Match UUID (salin dari hasil antrean)", InputType.TYPE_CLASS_TEXT);
        addButton(legacyGroup, "Periksa Status Match PvP", new Runnable() { @Override public void run() {
            final String id = value(pvpMatchId);
            runBackend("Status match PvP", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getPvpMatchState(id).toString();
            }});
        }});

        heading(legacyGroup, "5. World Boss (skor menunggu verifikasi)");
        addButton(legacyGroup, "Muat Siklus World Boss Aktif", new Runnable() { @Override public void run() {
            runBackend("Siklus World Boss", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getActiveWorldBossCycles().toString();
            }});
        }});
        cycleId = addInput(legacyGroup, "Cycle ID (salin dari hasil siklus)", InputType.TYPE_CLASS_TEXT);
        bossScore = addInput(legacyGroup, "Skor yang diajukan", InputType.TYPE_CLASS_NUMBER);
        addButton(legacyGroup, "Ranking World Boss", new Runnable() { @Override public void run() {
            final String cycle = value(cycleId);
            runBackend("Ranking World Boss", new BackendTask() { @Override public String execute() throws Exception {
                return backend.getWorldBossRankings(cycle, 100).toString();
            }});
        }});
        addButton(legacyGroup, "Ajukan Skor World Boss", new Runnable() { @Override public void run() {
            final String cycle = value(cycleId), score = value(bossScore);
            runBackend("Pengajuan skor World Boss", new BackendTask() { @Override public String execute() throws Exception {
                long number = Long.parseLong(score);
                return backend.submitWorldBossScoreClaim(cycle, number, new JSONObject()).toString();
            }});
        }});
        addButton(legacyGroup, "Lihat Pengajuan Skor Saya", new Runnable() { @Override public void run() {
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


    private void runGoogleBackend(final String title, final String action, final JSONObject payload) {
        output.setText(title + ": memuat...");
        executor.execute(new Runnable() {
            @Override public void run() {
                String result;
                try {
                    JSONObject data;
                    if ("get_state".equals(action)) data = googleBackend.getState();
                    else data = new JSONObject();
                    result = data.toString(2);
                } catch (Exception e) {
                    result = "Gagal: " + (e.getMessage() == null ? "Periksa login Google dan koneksi." : e.getMessage());
                }
                final String text = result;
                main.post(new Runnable() { @Override public void run() { output.setText(title + "\n" + text); } });
            }
        });
    }

    private void runBackend(final String label, final BackendTask task) {
        if (!backend.hasSession() && !"Daftar".equals(label) && !"Login".equals(label)) {
            output.setText("Login diperlukan untuk fitur ini. Silakan masuk ke Kingdom In Chaos DTP memakai Google.");
            startActivity(new Intent(GameOnlineHubActivity.this, GameAuthActivity.class));
            return;
        }
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
