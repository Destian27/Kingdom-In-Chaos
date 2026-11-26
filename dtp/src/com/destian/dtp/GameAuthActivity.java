package com.destian.dtp;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/**
 * Branded Google OAuth screen for Kingdom In Chaos DTP.
 * OAuth is handled by Supabase Auth in an external browser and returned through
 * kingdominchaosdtp://auth using PKCE. No Google client secret is stored in the APK.
 */
public final class GameAuthActivity extends Activity {
    private static final int BG_TOP = 0xFF101A31;
    private static final int BG_BOTTOM = 0xFF263B62;
    private static final int GOLD = 0xFFFFD36A;
    private static final int WHITE = Color.WHITE;
    private static final int MUTED = 0xFFD5DDF0;

    private final Handler main = new Handler(Looper.getMainLooper());
    private SupabaseGameBackend backend;
    private TextView status;
    private Button googleButton;
    private Button onlineButton;
    private boolean exchanging;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        backend = new SupabaseGameBackend(getApplicationContext());
        buildUi();
        Intent incoming = getIntent();
        if (incoming != null && incoming.getData() != null) {
            handleOAuthRedirect(incoming);
        } else if (backend.hasSession()) {
            status.setText("Sesi Kingdom In Chaos DTP tersimpan di perangkat ini.");
            onlineButton.setVisibility(View.VISIBLE);
        } else {
            status.setText("Masuk untuk memakai profil, avatar, dan fitur yang membutuhkan koneksi online.");
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Re-enable the button when the user returns from the browser without completing OAuth.
        if (!exchanging && googleButton != null) googleButton.setEnabled(true);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent != null && intent.getData() != null) handleOAuthRedirect(intent);
    }

    private void buildUi() {
        FrameLayout root = new FrameLayout(this);
        GradientDrawable background = new GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{BG_TOP, BG_BOTTOM});
        root.setBackground(background);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(dp(26), dp(24), dp(26), dp(24));

        FrameLayout.LayoutParams contentParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT);
        root.addView(content, contentParams);

        ImageView logo = new ImageView(this);
        int iconId = getResources().getIdentifier("icon", "drawable", getPackageName());
        if (iconId != 0) logo.setImageResource(iconId);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(dp(108), dp(108));
        logoParams.bottomMargin = dp(18);
        content.addView(logo, logoParams);

        TextView title = new TextView(this);
        title.setText("Login ke Kingdom In Chaos DTP");
        title.setTextColor(GOLD);
        title.setTextSize(23);
        title.setGravity(Gravity.CENTER);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        content.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Satu akun untuk menghubungkan profil, avatar, dan fitur online game.");
        subtitle.setTextColor(MUTED);
        subtitle.setTextSize(14);
        subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams subParams = matchWrap();
        subParams.topMargin = dp(12);
        subParams.bottomMargin = dp(24);
        content.addView(subtitle, subParams);

        googleButton = new Button(this);
        googleButton.setText("Lanjutkan dengan akun Google");
        googleButton.setAllCaps(false);
        googleButton.setTextColor(0xFF14213B);
        googleButton.setTextSize(15);
        googleButton.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        googleButton.setCompoundDrawablePadding(dp(10));
        Drawable gameIcon = iconId != 0 ? getResources().getDrawable(iconId) : null;
        if (gameIcon != null) {
            gameIcon = gameIcon.mutate();
            gameIcon.setBounds(0, 0, dp(30), dp(30));
            googleButton.setCompoundDrawables(gameIcon, null, null, null);
        }
        GradientDrawable buttonBg = new GradientDrawable();
        buttonBg.setColor(0xFFFFF4D6);
        buttonBg.setCornerRadius(dp(12));
        buttonBg.setStroke(dp(1), GOLD);
        googleButton.setBackgroundDrawable(buttonBg);
        googleButton.setPadding(dp(14), dp(12), dp(14), dp(12));
        googleButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { beginGoogleLogin(); }
        });
        LinearLayout.LayoutParams googleParams = matchWrap();
        googleParams.topMargin = dp(4);
        content.addView(googleButton, googleParams);

        status = new TextView(this);
        status.setTextColor(WHITE);
        status.setTextSize(13);
        status.setGravity(Gravity.CENTER);
        status.setPadding(dp(4), dp(18), dp(4), dp(12));
        content.addView(status, matchWrap());

        onlineButton = new Button(this);
        onlineButton.setText("Buka akun dan fitur online");
        onlineButton.setAllCaps(false);
        onlineButton.setVisibility(View.GONE);
        onlineButton.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) {
                startActivity(new Intent(GameAuthActivity.this, GameOnlineHubActivity.class));
                finish();
            }
        });
        LinearLayout.LayoutParams onlineParams = matchWrap();
        onlineParams.topMargin = dp(4);
        content.addView(onlineButton, onlineParams);

        Button back = new Button(this);
        back.setText("Kembali ke Game");
        back.setAllCaps(false);
        back.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { finish(); }
        });
        LinearLayout.LayoutParams backParams = matchWrap();
        backParams.topMargin = dp(8);
        content.addView(back, backParams);

        setContentView(root);
    }

    private void beginGoogleLogin() {
        if (exchanging) return;
        googleButton.setEnabled(false);
        status.setText("Menyiapkan koneksi aman ke Google melalui Supabase...");
        try {
            String url = backend.beginGoogleOAuth();
            Intent browser = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            startActivity(browser);
            status.setText("Selesaikan login pada browser. Setelah berhasil, game akan terbuka kembali otomatis.");
        } catch (Exception e) {
            status.setText("Tidak dapat membuka login: " + safeMessage(e));
            googleButton.setEnabled(true);
        }
    }

    private void handleOAuthRedirect(Intent intent) {
        Uri uri = intent.getData();
        if (uri == null || !"kingdominchaosdtp".equals(uri.getScheme())
                || !"auth".equals(uri.getHost())) {
            return;
        }

        String error = uri.getQueryParameter("error_description");
        if (error == null || error.trim().isEmpty()) error = uri.getQueryParameter("error");
        if (error != null && !error.trim().isEmpty()) {
            backend.clearGoogleOAuthPending();
            status.setText("Login Google tidak selesai: " + error);
            googleButton.setEnabled(true);
            return;
        }

        final String code = uri.getQueryParameter("code");
        final String returnedState = uri.getQueryParameter("state");
        if (code == null || code.trim().isEmpty()) {
            status.setText("Kode login tidak ditemukan. Silakan coba login lagi.");
            googleButton.setEnabled(true);
            return;
        }
        if (exchanging) return;

        exchanging = true;
        googleButton.setEnabled(false);
        onlineButton.setVisibility(View.GONE);
        status.setText("Memverifikasi akun dan menyimpan sesi Supabase...");
        Thread worker = new Thread(new Runnable() {
            @Override public void run() {
                String resultText;
                boolean success = false;
                try {
                    JSONObject session = backend.completeGoogleOAuth(code, returnedState);
                    JSONObject user = backend.currentUser();
                    String email = user.optString("email", "");
                    resultText = "Login berhasil" + (email.isEmpty() ? "." : " sebagai " + email + ".");
                    success = session.has("access_token") && backend.hasSession();
                } catch (Exception e) {
                    resultText = "Login gagal: " + safeMessage(e);
                }
                final String message = resultText;
                final boolean ok = success;
                main.post(new Runnable() {
                    @Override public void run() {
                        exchanging = false;
                        if (isFinishing()) return;
                        status.setText(message);
                        googleButton.setEnabled(!ok);
                        if (ok) {
                            onlineButton.setVisibility(View.VISIBLE);
                            setResult(RESULT_OK);
                        }
                    }
                });
            }
        }, "kic-google-oauth-exchange");
        worker.setDaemon(true);
        worker.start();
    }

    private static String safeMessage(Exception e) {
        String message = e.getMessage();
        return message == null || message.trim().isEmpty()
                ? e.getClass().getSimpleName() : message;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }
}
