package com.destian.dtp;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputFilter;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

/**
 * v17.14.10: layar "Daftar" bergaya perkamen game. Setelah Google terverifikasi pemain hanya
 * mengisi nama panggilan; ID Pemain dibuat server. Tidak ada tombol Masuk, Daftar-ganda, atau kata sandi.
 */
public final class GameProfileSetupActivity extends Activity {
    private static final int PARCHMENT = 0xFFB88A5A;
    private static final int PARCHMENT_EDGE = 0xFF6B4423;
    private static final int RIBBON = 0xFFA11F3A;
    private static final int FIELD = 0xFF8E6840;
    private static final int GOLD = 0xFFFFD36A;
    private static final int INK = 0xFF3B2410;

    private GooglePlayerBackend backend;
    private EditText nickname;
    private TextView status;
    private Button submit;
    private String playerId = "";
    private boolean saving;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        backend = new GooglePlayerBackend(getApplicationContext());
        playerId = getIntent().getStringExtra("player_id");
        if (playerId == null || playerId.trim().isEmpty()) playerId = "Dibuat oleh server";
        buildUi();
    }

    private void buildUi() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xE6101A14);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        root.addView(scroll, new FrameLayout.LayoutParams(-1, -1));

        FrameLayout holder = new FrameLayout(this);
        scroll.addView(holder, new FrameLayout.LayoutParams(-1, -2));

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setGravity(Gravity.CENTER_HORIZONTAL);
        panel.setPadding(dp(28), dp(44), dp(28), dp(24));
        GradientDrawable panelBg = new GradientDrawable();
        panelBg.setColor(PARCHMENT); panelBg.setCornerRadius(dp(10)); panelBg.setStroke(dp(3), PARCHMENT_EDGE);
        panel.setBackground(panelBg);
        FrameLayout.LayoutParams pp = new FrameLayout.LayoutParams(dp(380), -2, Gravity.CENTER);
        pp.topMargin = dp(28); pp.bottomMargin = dp(20);
        holder.addView(panel, pp);

        TextView ribbon = new TextView(this);
        ribbon.setText("Daftar"); ribbon.setTextSize(22); ribbon.setTextColor(GOLD);
        ribbon.setTypeface(Typeface.DEFAULT, Typeface.BOLD); ribbon.setGravity(Gravity.CENTER);
        GradientDrawable ribbonBg = new GradientDrawable();
        ribbonBg.setColor(RIBBON); ribbonBg.setCornerRadius(dp(6)); ribbonBg.setStroke(dp(2), 0xFF6E1226);
        ribbon.setBackground(ribbonBg); ribbon.setPadding(dp(30), dp(6), dp(30), dp(8));
        FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        rp.topMargin = dp(12);
        holder.addView(ribbon, rp);

        TextView close = new TextView(this);
        close.setText("X"); close.setTextSize(20); close.setTextColor(Color.WHITE);
        close.setTypeface(Typeface.DEFAULT, Typeface.BOLD); close.setGravity(Gravity.CENTER);
        GradientDrawable closeBg = new GradientDrawable();
        closeBg.setShape(GradientDrawable.OVAL); closeBg.setColor(0xFFC4452B); closeBg.setStroke(dp(3), 0xFFB9BEC6);
        close.setBackground(closeBg);
        close.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });
        FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams(dp(42), dp(42), Gravity.TOP | Gravity.RIGHT);
        cp.topMargin = dp(18); cp.rightMargin = dp(4);
        holder.addView(close, cp);

        TextView email = new TextView(this);
        String mail = getIntent().getStringExtra("email");
        email.setText("Google terverifikasi\n" + (mail == null ? "" : mail));
        email.setTextSize(13); email.setTextColor(INK); email.setGravity(Gravity.CENTER);
        panel.addView(email, matchWrap());

        panel.addView(label("ID Pemain", 18), labelParams(18));
        TextView idValue = new TextView(this);
        idValue.setText(playerId); idValue.setTextSize(18); idValue.setTextColor(Color.WHITE);
        idValue.setTypeface(Typeface.MONOSPACE, Typeface.BOLD); idValue.setGravity(Gravity.CENTER);
        idValue.setBackground(fieldBg()); idValue.setPadding(dp(12), dp(10), dp(12), dp(10));
        panel.addView(idValue, labelParams(6));

        panel.addView(label("Nama Panggilan", 16), labelParams(16));
        nickname = new EditText(this);
        nickname.setSingleLine(true); nickname.setHint("masukkan nama panggilan");
        nickname.setHintTextColor(0xFFE2D2BA); nickname.setTextColor(Color.WHITE); nickname.setTextSize(16);
        nickname.setFilters(new InputFilter[]{new InputFilter.LengthFilter(32)});
        nickname.setBackground(fieldBg()); nickname.setPadding(dp(12), dp(10), dp(12), dp(10));
        panel.addView(nickname, labelParams(6));

        status = new TextView(this);
        status.setTextColor(0xFF6E1226); status.setTextSize(13); status.setGravity(Gravity.CENTER);
        panel.addView(status, labelParams(12));

        submit = new Button(this);
        submit.setText("Daftar"); submit.setAllCaps(false); submit.setTextColor(Color.WHITE);
        submit.setTextSize(18); submit.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        GradientDrawable btnBg = new GradientDrawable();
        btnBg.setColor(0xFF2C5C9E); btnBg.setCornerRadius(dp(8)); btnBg.setStroke(dp(2), 0xFF16345E);
        submit.setBackground(btnBg);
        submit.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { saveProfile(); }
        });
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(dp(170), -2);
        bp.topMargin = dp(14); bp.gravity = Gravity.CENTER_HORIZONTAL;
        panel.addView(submit, bp);
        setContentView(root);
    }

    private TextView label(String text, int topDp) {
        TextView t = new TextView(this);
        t.setText(text); t.setTextSize(14); t.setTextColor(INK);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return t;
    }

    private LinearLayout.LayoutParams labelParams(int topDp) {
        LinearLayout.LayoutParams lp = matchWrap(); lp.topMargin = dp(topDp); return lp;
    }

    private GradientDrawable fieldBg() {
        GradientDrawable g = new GradientDrawable();
        g.setColor(FIELD); g.setCornerRadius(dp(6)); g.setStroke(dp(1), PARCHMENT_EDGE);
        return g;
    }

    private void saveProfile() {
        final String name = nickname.getText().toString().trim();
        if (name.length() < 3 || name.length() > 32) {
            status.setText("Nama panggilan harus terdiri dari 3–32 karakter."); return;
        }
        if (saving) return;
        saving = true; submit.setEnabled(false); status.setText("Menyimpan profil...");
        Thread worker = new Thread(new Runnable() {
            @Override public void run() {
                JSONObject result = null; Exception failure = null;
                try { result = backend.completeProfile(name); } catch (Exception e) { failure = e; }
                final JSONObject data = result; final Exception error = failure;
                runOnUiThread(new Runnable() {
                    @Override public void run() {
                        saving = false; submit.setEnabled(true);
                        if (error != null) { status.setText("Tidak dapat menyimpan profil: " + error.getMessage()); return; }
                        JSONObject savedProfile = data == null ? null : data.optJSONObject("profile");
                        String id = savedProfile == null ? playerId : savedProfile.optString("player_id", playerId);
                        status.setText("Berhasil terdaftar. ID Pemain: " + id);
                        getIntent().putExtra("player_id", id);
                        startActivity(new android.content.Intent(GameProfileSetupActivity.this, GameOnlineHubActivity.class));
                        finish();
                    }
                });
            }
        }, "kic-google-profile-setup");
        worker.setDaemon(true); worker.start();
    }

    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density + 0.5f); }
    private static LinearLayout.LayoutParams matchWrap() { return new LinearLayout.LayoutParams(-1, -2); }
}
