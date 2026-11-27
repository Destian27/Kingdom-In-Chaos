package com.destian.dtp;

import android.accounts.AccountManager;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/** Direct Google account sign-in. No game password or Supabase Auth login form. */
public final class GameAuthActivity extends Activity {
    private static final int BG_TOP = 0xFF101A31;
    private static final int BG_BOTTOM = 0xFF263B62;
    private static final int GOLD = 0xFFFFD36A;
    private static final int WHITE = Color.WHITE;
    private static final int MUTED = 0xFFD5DDF0;
    private static final int REQUEST_GOOGLE_ACCOUNT = 5101;
    private static final int REQUEST_GOOGLE_RECOVERY = 5102;

    private GooglePlayerBackend backend;
    private TextView status;
    private Button googleButton;
    private boolean busy;
    private String pendingAccountName = "";

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        backend = new GooglePlayerBackend(getApplicationContext());
        buildUi();
        if (backend.hasAccount()) {
            status.setText("Memeriksa akun Google yang tersimpan...");
            authenticate(backend.getSavedAccountName());
        } else {
            status.setText("Login memakai akun Google. Email harus sudah diverifikasi oleh Google.");
        }
    }

    private void buildUi() {
        FrameLayout root = new FrameLayout(this);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{BG_TOP, BG_BOTTOM}));
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(dp(26), dp(24), dp(26), dp(24));
        root.addView(content, new FrameLayout.LayoutParams(-1, -1));

        ImageView logo = new ImageView(this);
        int iconId = getResources().getIdentifier("icon", "drawable", getPackageName());
        if (iconId != 0) logo.setImageResource(iconId);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(dp(108), dp(108));
        logoParams.bottomMargin = dp(18);
        content.addView(logo, logoParams);

        TextView title = new TextView(this);
        title.setText("Login Google — Kingdom In Chaos DTP");
        title.setTextColor(GOLD); title.setTextSize(22); title.setGravity(Gravity.CENTER);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        content.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Gunakan akun Google. Tidak perlu password atau konfirmasi password game.");
        subtitle.setTextColor(MUTED); subtitle.setTextSize(14); subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams sub = matchWrap(); sub.topMargin = dp(12); sub.bottomMargin = dp(24);
        content.addView(subtitle, sub);

        googleButton = new Button(this);
        googleButton.setText("Lanjutkan dengan Google");
        googleButton.setAllCaps(false); googleButton.setTextColor(0xFF14213B);
        googleButton.setTextSize(15); googleButton.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        googleButton.setCompoundDrawablePadding(dp(10));
        int googleIconId = getResources().getIdentifier("google_logo", "drawable", getPackageName());
        Drawable icon = googleIconId != 0 ? getResources().getDrawable(googleIconId) : null;
        if (icon != null) { icon = icon.mutate(); icon.setBounds(0, 0, dp(26), dp(26)); googleButton.setCompoundDrawables(icon, null, null, null); }
        GradientDrawable buttonBg = new GradientDrawable(); buttonBg.setColor(0xFFFFF4D6);
        buttonBg.setCornerRadius(dp(12)); buttonBg.setStroke(dp(1), GOLD);
        googleButton.setBackgroundDrawable(buttonBg); googleButton.setPadding(dp(14), dp(12), dp(14), dp(12));
        googleButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { chooseGoogleAccount(); }
        });
        LinearLayout.LayoutParams buttonParams = matchWrap(); buttonParams.topMargin = dp(4);
        content.addView(googleButton, buttonParams);

        status = new TextView(this); status.setTextColor(WHITE); status.setTextSize(13);
        status.setGravity(Gravity.CENTER); status.setPadding(dp(4), dp(18), dp(4), dp(12));
        content.addView(status, matchWrap());

        Button back = new Button(this); back.setText("Kembali ke Game"); back.setAllCaps(false);
        back.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { finish(); } });
        LinearLayout.LayoutParams backParams = matchWrap(); backParams.topMargin = dp(8);
        content.addView(back, backParams);
        setContentView(root);
    }

    private void chooseGoogleAccount() {
        if (busy) return;
        try {
            Intent chooser = AccountManager.newChooseAccountIntent(
                    null, null, new String[]{"com.google"}, true,
                    "Pilih akun Google untuk Kingdom In Chaos DTP", null, null, null);
            startActivityForResult(chooser, REQUEST_GOOGLE_ACCOUNT);
            status.setText("Pilih akun Google yang akan digunakan.");
        } catch (Exception e) {
            status.setText("Tidak dapat membuka pemilih akun Google: " + safeMessage(e));
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null) {
            if (requestCode == REQUEST_GOOGLE_ACCOUNT) status.setText("Pemilihan akun dibatalkan.");
            return;
        }
        if (requestCode == REQUEST_GOOGLE_ACCOUNT) {
            String account = data.getStringExtra(AccountManager.KEY_ACCOUNT_NAME);
            if (account == null || account.trim().isEmpty()) {
                status.setText("Nama akun Google tidak diterima oleh Android."); return;
            }
            authenticate(account.trim());
        } else if (requestCode == REQUEST_GOOGLE_RECOVERY) {
            if (!pendingAccountName.isEmpty()) authenticate(pendingAccountName);
        }
    }

    private void authenticate(final String accountName) {
        if (busy) return;
        busy = true; pendingAccountName = accountName;
        googleButton.setEnabled(false);
        status.setText("Memverifikasi akun Google dan menyiapkan profil pemain...");
        Thread worker = new Thread(new Runnable() {
            @Override public void run() {
                JSONObject result = null; Exception failure = null;
                try { result = backend.loginWithGoogleAccount(accountName); }
                catch (Exception e) { failure = e; }
                final JSONObject data = result; final Exception error = failure;
                runOnUiThread(new Runnable() {
                    @Override public void run() {
                        busy = false; googleButton.setEnabled(true);
                        if (isFinishing()) return;
                        if (error != null) {
                            if (error instanceof GooglePlayerBackend.RecoverableGoogleAuthException) {
                                Intent recovery = ((GooglePlayerBackend.RecoverableGoogleAuthException) error).getRecoveryIntent();
                                try { startActivityForResult(recovery, REQUEST_GOOGLE_RECOVERY); }
                                catch (Exception ignored) { status.setText("Persetujuan Google tidak dapat dibuka. Coba lagi."); }
                            } else {
                                status.setText("Login Google gagal: " + safeMessage(error));
                            }
                            return;
                        }
                        JSONObject profile = data == null ? null : data.optJSONObject("profile");
                        if (profile == null) { status.setText("Profil pemain tidak diterima dari server."); return; }
                        if (!profile.optBoolean("profile_completed", false)) {
                            Intent setup = new Intent(GameAuthActivity.this, GameProfileSetupActivity.class);
                            setup.putExtra("player_uuid", profile.optString("player_uuid", ""));
                            setup.putExtra("player_id", profile.optString("player_id", ""));
                            setup.putExtra("email", profile.optString("email", accountName));
                            setup.putExtra("avatar_url", profile.optString("avatar_url", ""));
                            startActivity(setup);
                        } else {
                            status.setText("Akun Google terverifikasi. Selamat datang, " + profile.optString("nickname", "Pemain") + ".");
                            startActivity(new Intent(GameAuthActivity.this, GameOnlineHubActivity.class));
                        }
                        finish();
                    }
                });
            }
        }, "kic-direct-google-login");
        worker.setDaemon(true); worker.start();
    }

    private static String safeMessage(Exception e) {
        String message = e == null ? null : e.getMessage();
        return message == null || message.trim().isEmpty() ? "Periksa akun Google dan koneksi internet." : message;
    }
    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density + 0.5f); }
    private static LinearLayout.LayoutParams matchWrap() { return new LinearLayout.LayoutParams(-1, -2); }
}
