package com.destian.dtp;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputFilter;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/** First-run profile completion after a verified Google sign-in. */
public final class GameProfileSetupActivity extends Activity {
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
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(24), dp(24), dp(24), dp(24));
        GradientDrawable bg = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{0xFFFFF6E4, 0xFFE9F1FF});
        root.setBackground(bg);

        TextView title = new TextView(this); title.setText("Buat Profil Pemain");
        title.setTextSize(25); title.setTextColor(0xFF52351A); title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER); root.addView(title, matchWrap());

        TextView email = new TextView(this);
        email.setText("Google terverifikasi\n" + getIntent().getStringExtra("email"));
        email.setTextSize(14); email.setTextColor(0xFF5F6470); email.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams ep = matchWrap(); ep.topMargin = dp(14); root.addView(email, ep);

        TextView idLabel = new TextView(this); idLabel.setText("ID PEMAIN"); idLabel.setTextSize(13);
        idLabel.setTextColor(0xFF6F4A20); idLabel.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        LinearLayout.LayoutParams lp = matchWrap(); lp.topMargin = dp(26); root.addView(idLabel, lp);
        TextView idValue = new TextView(this); idValue.setText(playerId); idValue.setTextSize(20);
        idValue.setTextColor(0xFF193D78); idValue.setGravity(Gravity.CENTER);
        idValue.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        GradientDrawable idBg = new GradientDrawable(); idBg.setColor(Color.WHITE); idBg.setCornerRadius(dp(10)); idBg.setStroke(dp(1), 0xFFCBD8EC);
        idValue.setBackground(idBg); idValue.setPadding(dp(14), dp(14), dp(14), dp(14));
        LinearLayout.LayoutParams ivp = matchWrap(); ivp.topMargin = dp(8); root.addView(idValue, ivp);

        TextView nameLabel = new TextView(this); nameLabel.setText("NICKNAME"); nameLabel.setTextSize(13);
        nameLabel.setTextColor(0xFF6F4A20); nameLabel.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        LinearLayout.LayoutParams nlp = matchWrap(); nlp.topMargin = dp(24); root.addView(nameLabel, nlp);
        nickname = new EditText(this); nickname.setSingleLine(true); nickname.setHint("Masukkan nama panggilan");
        nickname.setTextSize(16); nickname.setFilters(new InputFilter[]{new InputFilter.LengthFilter(32)});
        nickname.setPadding(dp(12), dp(12), dp(12), dp(12));
        GradientDrawable inputBg = new GradientDrawable(); inputBg.setColor(Color.WHITE); inputBg.setCornerRadius(dp(10)); inputBg.setStroke(dp(1), 0xFFCBD8EC);
        nickname.setBackground(inputBg);
        LinearLayout.LayoutParams np = matchWrap(); np.topMargin = dp(8); root.addView(nickname, np);

        status = new TextView(this); status.setTextColor(0xFF7A2C1A); status.setTextSize(13);
        status.setGravity(Gravity.CENTER); LinearLayout.LayoutParams sp = matchWrap(); sp.topMargin = dp(14); root.addView(status, sp);

        submit = new Button(this); submit.setText("Simpan Profil dan Lanjutkan"); submit.setAllCaps(false);
        submit.setOnClickListener(v -> saveProfile());
        LinearLayout.LayoutParams bp = matchWrap(); bp.topMargin = dp(20); root.addView(submit, bp);
        setContentView(root);
    }

    private void saveProfile() {
        final String name = nickname.getText().toString().trim();
        if (name.length() < 3 || name.length() > 32) {
            status.setText("Nickname harus terdiri dari 3–32 karakter."); return;
        }
        if (saving) return;
        saving = true; submit.setEnabled(false); status.setText("Menyimpan profil...");
        Thread worker = new Thread(() -> {
            JSONObject result = null; Exception failure = null;
            try { result = backend.completeProfile(name); } catch (Exception e) { failure = e; }
            final JSONObject data = result; final Exception error = failure;
            runOnUiThread(() -> {
                saving = false; submit.setEnabled(true);
                if (error != null) { status.setText("Tidak dapat menyimpan profil: " + error.getMessage()); return; }
                JSONObject savedProfile = data == null ? null : data.optJSONObject("profile");
                String id = savedProfile == null ? playerId : savedProfile.optString("player_id", playerId);
                status.setText("Profil berhasil dibuat. ID Pemain: " + id);
                getIntent().putExtra("player_id", id);
                startActivity(new android.content.Intent(GameProfileSetupActivity.this, GameOnlineHubActivity.class));
                finish();
            });
        }, "kic-google-profile-setup");
        worker.setDaemon(true); worker.start();
    }

    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density + 0.5f); }
    private static LinearLayout.LayoutParams matchWrap() { return new LinearLayout.LayoutParams(-1, -2); }
}
