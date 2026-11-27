package com.destian.dtp;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputFilter;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/** Player-side reward-code redemption page backed by a server-verified Google identity. */
public final class GameGiftCodeActivity extends Activity {
    private GooglePlayerBackend backend;
    private EditText codeInput;
    private TextView status;
    private Button redeemButton;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        backend = new GooglePlayerBackend(this);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(20), dp(22), dp(20), dp(22));
        TextView title = new TextView(this); title.setText("KODE HADIAH"); title.setTextSize(24); title.setGravity(Gravity.CENTER);
        page.addView(title, matchWrap());
        TextView hint = new TextView(this); hint.setText("Masukkan kode hadiah dari event atau pengumuman resmi."); hint.setTextSize(14);
        LinearLayout.LayoutParams hp = matchWrap(); hp.topMargin = dp(12); page.addView(hint, hp);
        codeInput = new EditText(this); codeInput.setSingleLine(true); codeInput.setHint("MASUKKAN KODE HADIAH");
        codeInput.setFilters(new InputFilter[]{new InputFilter.AllCaps(), new InputFilter.LengthFilter(40)});
        LinearLayout.LayoutParams ip = matchWrap(); ip.topMargin = dp(18); page.addView(codeInput, ip);
        redeemButton = new Button(this); redeemButton.setText("Klaim Hadiah"); redeemButton.setAllCaps(false);
        redeemButton.setOnClickListener(v -> redeem());
        LinearLayout.LayoutParams bp = matchWrap(); bp.topMargin = dp(14); page.addView(redeemButton, bp);
        status = new TextView(this); status.setTextSize(13); status.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams sp = matchWrap(); sp.topMargin = dp(16); page.addView(status, sp);
        Button back = new Button(this); back.setText("Kembali"); back.setAllCaps(false); back.setOnClickListener(v -> finish());
        LinearLayout.LayoutParams backp = matchWrap(); backp.topMargin = dp(12); page.addView(back, backp);
        setContentView(page);
    }

    private void redeem() {
        String value = codeInput.getText().toString().trim().toUpperCase(java.util.Locale.ROOT);
        if (!value.matches("[A-Z0-9-]{4,40}")) { status.setText("Kode harus 4–40 karakter (huruf, angka, atau -)."); return; }
        redeemButton.setEnabled(false); status.setText("Memeriksa kode dan memproses hadiah...");
        new Thread(() -> {
            JSONObject result = null; Exception error = null;
            try { result = backend.redeemGiftCode(value); } catch (Exception e) { error = e; }
            final JSONObject data = result; final Exception failure = error;
            runOnUiThread(() -> {
                redeemButton.setEnabled(true);
                if (failure != null) { status.setText("Kode tidak dapat diklaim: " + failure.getMessage()); return; }
                JSONObject wallet = data == null ? null : data.optJSONObject("economy");
                status.setText("Kode berhasil diklaim!\nSaldo terbaru: " + (wallet == null ? "Hadiah masuk ke akun." : "Koin " + wallet.optString("coins", "0") + " • DM " + wallet.optString("crystals", "0") + " • Daging " + wallet.optString("meat", "0")));
                codeInput.setText("");
            });
        }, "kic-redeem-gift-code").start();
    }

    private int dp(int n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private static LinearLayout.LayoutParams matchWrap() { return new LinearLayout.LayoutParams(-1, -2); }
}
