package com.destian.dtp;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class MaintenanceActivity extends Activity {

    private static final String SUPABASE_URL = "https://gunzwimrxspbmiducphg.supabase.co/rest/v1/";
    static final String SUPABASE_ANON_KEY =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1bnp3aW1yeHNwYm1pZHVjcGhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU2Njk0NDYsImV4cCI6MjExMTI0NTQ0Nn0.OQn69Q-IZ4k1ZyXc6hk8oBi7vFyOBfWTgRUXuKZqocY";
    private static final String TABLE = "app_maintenance";

    private static final boolean BLOCK_WHEN_OFFLINE = true;
    private static final int TIMEOUT_MS = 8000;
    private static final int RECHECK_SECONDS = 3;
    private static final String GAME_ACTIVITY = "com.droidhang.ph.GameActivity";

    private static final int GOLD = 0xFFF2C14E;
    private static final int TEXT_LIGHT = 0xFFEADCC6;
    private static final int TEXT_DIM = 0xFFB79C7A;
    private static final int TEXT_ERROR = 0xFFE57373;

    static final class Result {
        boolean ok;
        boolean active;
        String title;
        String message;
        long startMs;
        long endMs;
        long serverNow;
        String error;
    }

    private final Handler handler = new Handler(Looper.getMainLooper());

    private boolean checking;
    private boolean pendingRecheck;
    private RealtimeClient rt;
    private boolean destroyed;
    private boolean launched;
    private boolean maintenanceShown;
    private boolean blockedOffline;
    private long endMs;
    private long serverNowAtFetch;
    private long elapsedAtFetch;
    private int tickCount;

    private TextView titleView;
    private TextView statusView;
    private TextView messageView;
    private TextView endInfoView;
    private TextView noteView;
    private ProgressBar loadingBar;
    private LinearLayout countdownRow;
    private LinearLayout buttonRow;
    private final TextView[] boxNumbers = new TextView[4];

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            if (destroyed || launched) {
                return;
            }
            updateCountdown();
            tickCount++;
            boolean over = endMs > 0 && remainingMs() <= 0;
            if ((over && tickCount % 3 == 0) || tickCount % RECHECK_SECONDS == 0) {
                startCheck(true);
            }
            handler.postDelayed(this, 1000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setContentView(buildUi());
        showLoading();
        startCheck(false);
    }

    @Override
    protected void onResume() {
        super.onResume();
        startRt();
        if (maintenanceShown && !launched) {
            handler.removeCallbacks(tick);
            handler.postDelayed(tick, 1000);
            startCheck(true);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        stopRt();
        handler.removeCallbacks(tick);
    }

    @Override
    protected void onDestroy() {
        destroyed = true;
        stopRt();
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        // The maintenance/unverified-server gate is intentionally non-dismissible.
        if (maintenanceShown || blockedOffline || !launched) return;
        super.onBackPressed();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
    }

    private int dp(float v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String s, float sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER);
        if (bold) {
            t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        }
        return t;
    }

    private LinearLayout.LayoutParams lp(int w, int h, int top) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(w, h);
        p.gravity = Gravity.CENTER_HORIZONTAL;
        p.topMargin = dp(top);
        return p;
    }

    private LinearLayout makeBox(int index, String label) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(10), dp(8), dp(10), dp(8));
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(10));
        bg.setColor(0x66000000);
        bg.setStroke(dp(1), GOLD);
        box.setBackgroundDrawable(bg);

        TextView num = text("00", 34, Color.WHITE, true);
        num.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        num.setMinWidth(dp(70));
        boxNumbers[index] = num;
        box.addView(num, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView lab = text(label, 11, GOLD, true);
        box.addView(lab, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return box;
    }

    private Button makeButton(String label, int fill, int fg) {
        Button b = new Button(this);
        b.setText(label);
        b.setTextColor(fg);
        b.setTextSize(14);
        b.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        b.setAllCaps(true);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(10));
        bg.setColor(fill);
        bg.setStroke(dp(1), GOLD);
        b.setBackgroundDrawable(bg);
        b.setPadding(dp(22), dp(8), dp(22), dp(8));
        return b;
    }

    private View buildUi() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundDrawable(new GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM, new int[]{0xFF140B08, 0xFF3A1A0D}));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        root.addView(scroll, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER);
        content.setPadding(dp(24), dp(16), dp(24), dp(16));
        scroll.addView(content, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        titleView = text("KINGDOM IN CHAOS DTP", 24, GOLD, true);
        content.addView(titleView, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 0));

        statusView = text("", 19, Color.WHITE, true);
        content.addView(statusView, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 10));

        messageView = text("", 14, TEXT_LIGHT, false);
        content.addView(messageView, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 8));

        loadingBar = new ProgressBar(this);
        loadingBar.setIndeterminate(true);
        content.addView(loadingBar, lp(dp(36), dp(36), 14));

        countdownRow = new LinearLayout(this);
        countdownRow.setOrientation(LinearLayout.HORIZONTAL);
        countdownRow.setGravity(Gravity.CENTER);
        String[] labels = {"HARI", "JAM", "MENIT", "DETIK"};
        for (int i = 0; i < 4; i++) {
            LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            bp.leftMargin = dp(5);
            bp.rightMargin = dp(5);
            countdownRow.addView(makeBox(i, labels[i]), bp);
        }
        content.addView(countdownRow, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 16));

        endInfoView = text("", 13, TEXT_DIM, false);
        content.addView(endInfoView, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 12));

        noteView = text("", 12, TEXT_ERROR, false);
        content.addView(noteView, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 6));

        buttonRow = new LinearLayout(this);
        buttonRow.setOrientation(LinearLayout.HORIZONTAL);
        buttonRow.setGravity(Gravity.CENTER);
        Button retry = makeButton("Cek Lagi", 0xFF7A3A12, Color.WHITE);
        retry.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                noteView.setText("");
                startCheck(true);
            }
        });
        Button exit = makeButton("Tutup Game", 0x66000000, GOLD);
        exit.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                // Close the task; never return to a game activity behind this gate.
                finishAndRemoveTask();
            }
        });
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bp.leftMargin = dp(6);
        bp.rightMargin = dp(6);
        buttonRow.addView(retry, bp);
        buttonRow.addView(exit, bp);
        content.addView(buttonRow, lp(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, 16));

        return root;
    }

    private void showLoading() {
        statusView.setText("Memeriksa server...");
        messageView.setText("");
        endInfoView.setText("");
        noteView.setText("");
        loadingBar.setVisibility(View.VISIBLE);
        countdownRow.setVisibility(View.GONE);
        buttonRow.setVisibility(View.GONE);
    }

    private void showError() {
        blockedOffline = true;
        statusView.setText("AKSES DITAHAN — SERVER TIDAK DAPAT DIVERIFIKASI");
        messageView.setText("Game tidak dapat dibuka sebelum status maintenance berhasil diverifikasi. Periksa koneksi lalu tekan Cek Lagi.");
        endInfoView.setText("");
        loadingBar.setVisibility(View.GONE);
        countdownRow.setVisibility(View.GONE);
        buttonRow.setVisibility(View.VISIBLE);
        // Automatically retry in case connectivity returns; Back/Exit cannot reopen GameActivity.
        handler.removeCallbacks(tick);
        tickCount = 0;
        handler.postDelayed(tick, 1000);
    }

    private void showMaintenance(Result r) {
        maintenanceShown = true;
        endMs = r.endMs;
        statusView.setText(r.title != null && r.title.length() > 0 ? r.title : "SEDANG MAINTENANCE");
        String msg = r.message != null && r.message.length() > 0
                ? r.message
                : "Game sedang dalam perbaikan. Silakan kembali beberapa saat lagi.";
        messageView.setText(msg);
        loadingBar.setVisibility(View.GONE);
        buttonRow.setVisibility(View.VISIBLE);
        noteView.setText("");

        if (endMs > 0) {
            countdownRow.setVisibility(View.VISIBLE);
            SimpleDateFormat f = new SimpleDateFormat("EEEE, d MMMM yyyy HH:mm", new Locale("id", "ID"));
            TimeZone tz = TimeZone.getDefault();
            f.setTimeZone(tz);
            endInfoView.setText("Perkiraan selesai: " + f.format(new Date(endMs))
                    + " " + tz.getDisplayName(tz.inDaylightTime(new Date(endMs)), TimeZone.SHORT, Locale.US));
        } else {
            countdownRow.setVisibility(View.GONE);
            endInfoView.setText("Waktu selesai belum ditentukan. Mohon tunggu pengumuman berikutnya.");
        }

        handler.removeCallbacks(tick);
        tickCount = 0;
        updateCountdown();
        handler.postDelayed(tick, 1000);
    }

    private long serverNow() {
        return serverNowAtFetch + (SystemClock.elapsedRealtime() - elapsedAtFetch);
    }

    private long remainingMs() {
        long rem = endMs - serverNow();
        return rem < 0 ? 0 : rem;
    }

    private void updateCountdown() {
        if (endMs <= 0) {
            return;
        }
        long total = remainingMs() / 1000L;
        long days = total / 86400L;
        long hours = (total % 86400L) / 3600L;
        long minutes = (total % 3600L) / 60L;
        long seconds = total % 60L;
        boxNumbers[0].setText(String.format(Locale.US, "%02d", days));
        boxNumbers[1].setText(String.format(Locale.US, "%02d", hours));
        boxNumbers[2].setText(String.format(Locale.US, "%02d", minutes));
        boxNumbers[3].setText(String.format(Locale.US, "%02d", seconds));
    }

    private void startRt() {
        if (rt != null || launched || destroyed) {
            return;
        }
        rt = new RealtimeClient(new RealtimeClient.Listener() {
            @Override
            public void onChange() {
                handler.post(new Runnable() {
                    @Override
                    public void run() {
                        if (!destroyed && !launched) {
                            startCheck(true);
                        }
                    }
                });
            }
        });
        rt.start();
    }

    private void stopRt() {
        if (rt != null) {
            rt.stop();
            rt = null;
        }
    }

    private void startCheck(final boolean silent) {
        if (checking || launched) {
            if (checking) {
                pendingRecheck = true;
            }
            return;
        }
        checking = true;
        if (!silent) {
            showLoading();
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                final Result r = fetchStatus();
                handler.post(new Runnable() {
                    @Override
                    public void run() {
                        checking = false;
                        if (destroyed) {
                            return;
                        }
                        onResult(r);
                        if (pendingRecheck) {
                            pendingRecheck = false;
                            startCheck(true);
                        }
                    }
                });
            }
        }).start();
    }

    private void onResult(Result r) {
        if (!r.ok) {
            if (BLOCK_WHEN_OFFLINE) {
                showError();
                String detail = r.error != null && r.error.length() > 0 ? "\nDetail: " + r.error : "";
                noteView.setText("Pemeriksaan server gagal. Akses tetap ditahan; game tidak akan dibuka tanpa status server yang valid." + detail);
            } else {
                launchGame();
            }
            return;
        }
        blockedOffline = false;
        serverNowAtFetch = r.serverNow;
        elapsedAtFetch = SystemClock.elapsedRealtime();
        boolean underMaintenance = r.active
                && (r.startMs <= 0 || r.serverNow >= r.startMs)
                && (r.endMs <= 0 || r.serverNow < r.endMs);
        if (underMaintenance) {
            showMaintenance(r);
        } else {
            launchGame();
        }
    }

    private void launchGame() {
        if (launched) {
            return;
        }
        launched = true;
        handler.removeCallbacksAndMessages(null);
        Intent i = new Intent();
        i.setClassName(this, GAME_ACTIVITY);
        startActivity(i);
        overridePendingTransition(0, 0);
        finish();
    }

    static Result fetchStatus() {
        Result r = new Result();
        HttpURLConnection c = null;
        try {
            URL url = new URL(SUPABASE_URL + TABLE + "?select=*&id=eq.1&limit=1");
            c = (HttpURLConnection) url.openConnection();
            c.setConnectTimeout(TIMEOUT_MS);
            c.setReadTimeout(TIMEOUT_MS);
            c.setUseCaches(false);
            c.setRequestMethod("GET");
            c.setRequestProperty("apikey", SUPABASE_ANON_KEY);
            c.setRequestProperty("Authorization", "Bearer " + SUPABASE_ANON_KEY);
            c.setRequestProperty("Accept", "application/json");
            c.setRequestProperty("Cache-Control", "no-cache");
            int code = c.getResponseCode();
            if (code != 200) {
                throw new IOException("HTTP " + code);
            }
            long date = c.getDate();
            String body = readAll(c.getInputStream());
            JSONArray arr = new JSONArray(body);
            if (arr.length() != 1) throw new IOException("Maintenance config missing or duplicated");
            JSONObject o = arr.getJSONObject(0);
            if (!o.has("is_active") || o.isNull("is_active")) {
                throw new IOException("Maintenance config is invalid");
            }
            r.serverNow = date > 0 ? date : System.currentTimeMillis();
            r.active = o.optBoolean("is_active", true);
            r.title = str(o, "title");
            r.message = str(o, "message");
            r.startMs = parseTime(str(o, "start_at"));
            r.endMs = parseTime(str(o, "end_at"));
            r.ok = true;
        } catch (Exception e) {
            r.ok = false;
            String msg = String.valueOf(e.getMessage());
            if (msg.length() > 90) msg = msg.substring(0, 90);
            r.error = e.getClass().getSimpleName() + ": " + msg;
        } finally {
            if (c != null) {
                c.disconnect();
            }
        }
        return r;
    }

    private static String str(JSONObject o, String key) {
        return o.isNull(key) ? null : o.optString(key, null);
    }

    private static String readAll(InputStream in) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(in, "UTF-8"));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = br.readLine()) != null) {
            sb.append(line);
        }
        br.close();
        return sb.toString();
    }

    private static long parseTime(String s) {
        if (s == null) {
            return 0;
        }
        s = s.trim().replace(' ', 'T');
        if (s.length() == 0) {
            return 0;
        }
        s = s.replaceFirst("\\.\\d+", "");
        if (s.matches(".*T.*[+-]\\d\\d$")) {
            s = s + ":00";
        }
        try {
            Date d = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).parse(s);
            return d == null ? 0 : d.getTime();
        } catch (ParseException e) {
            try {
                SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US);
                f.setTimeZone(TimeZone.getTimeZone("UTC"));
                Date d = f.parse(s);
                return d == null ? 0 : d.getTime();
            } catch (ParseException e2) {
                return 0;
            }
        }
    }
}
