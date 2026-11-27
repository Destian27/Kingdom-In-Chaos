package com.destian.dtp;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/** Account-side cloud meat wallet for admin/reward tracking; native mission food is handled by the original game engine. */
public final class GameMeatActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private GooglePlayerBackend backend;
    private TextView meatCount, dmCount, timer, status;
    private Button buyButton, consumeButton;
    private int currentMeat, capacity = 24, secondsToNext, dmPerMeat = 1;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        backend = new GooglePlayerBackend(this);
        buildUi();
        refreshState();
    }

    private void buildUi() {
        LinearLayout page = new LinearLayout(this); page.setOrientation(LinearLayout.VERTICAL);
        page.setGravity(Gravity.CENTER_HORIZONTAL); page.setPadding(dp(20), dp(20), dp(20), dp(20));
        TextView title = new TextView(this); title.setText("DAGING MISI"); title.setTextSize(24); title.setGravity(Gravity.CENTER);
        page.addView(title, matchWrap());
        meatCount = new TextView(this); meatCount.setTextSize(34); meatCount.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams cp = matchWrap(); cp.topMargin = dp(20); page.addView(meatCount, cp);
        timer = new TextView(this); timer.setTextSize(14); timer.setGravity(Gravity.CENTER);
        page.addView(timer, matchWrap());
        dmCount = new TextView(this); dmCount.setTextSize(16); dmCount.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams dmParams = matchWrap(); dmParams.topMargin = dp(10); page.addView(dmCount, dmParams);
        buyButton = new Button(this); buyButton.setAllCaps(false); buyButton.setText("Beli +1 Daging dengan DM");
        buyButton.setOnClickListener(v -> buyOne());
        LinearLayout.LayoutParams bp = matchWrap(); bp.topMargin = dp(18); page.addView(buyButton, bp);
        consumeButton = new Button(this); consumeButton.setAllCaps(false); consumeButton.setText("Gunakan 1 Daging untuk Misi");
        consumeButton.setOnClickListener(v -> consumeOne());
        LinearLayout.LayoutParams up = matchWrap(); up.topMargin = dp(8); page.addView(consumeButton, up);
        status = new TextView(this); status.setTextSize(13); status.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams sp = matchWrap(); sp.topMargin = dp(14); page.addView(status, sp);
        Button refresh = new Button(this); refresh.setText("Muat Ulang"); refresh.setAllCaps(false); refresh.setOnClickListener(v -> refreshState());
        page.addView(refresh, matchWrap());
        Button back = new Button(this); back.setText("Kembali"); back.setAllCaps(false); back.setOnClickListener(v -> finish());
        page.addView(back, matchWrap());
        setContentView(page);
    }

    private void refreshState() {
        handler.removeCallbacksAndMessages(null);
        status.setText("Memuat saldo daging dan DM...");
        new Thread(() -> {
            JSONObject result = null; Exception error = null;
            try { result = backend.getState(); } catch (Exception e) { error = e; }
            final JSONObject data = result; final Exception failure = error;
            runOnUiThread(() -> {
                if (failure != null) { status.setText("Gagal memuat: " + failure.getMessage()); return; }
                JSONObject economy = data == null ? null : data.optJSONObject("economy");
                if (economy == null) { status.setText("Data saldo tidak tersedia."); return; }
                currentMeat = economy.optInt("meat", 0);
                capacity = data.optInt("meat_capacity", 24);
                secondsToNext = data.optInt("meat_seconds_to_next", 0);
                dmPerMeat = data.optInt("dm_per_meat", 1);
                int dm = economy.optInt("crystals", 0);
                meatCount.setText("DAGING  " + currentMeat + " / " + capacity);
                dmCount.setText("DM tersedia: " + dm + " • Harga: " + dmPerMeat + " DM / daging");
                status.setText(currentMeat <= 0 ? "Daging habis. Beli daging menggunakan DM." : "Daging siap digunakan untuk misi.");
                buyButton.setEnabled(currentMeat < capacity);
                consumeButton.setEnabled(currentMeat > 0);
                updateTimerText();
            });
        }, "kic-meat-state").start();
    }

    private void buyOne() {
        buyButton.setEnabled(false); status.setText("Membeli 1 daging...");
        new Thread(() -> {
            JSONObject result = null; Exception error = null;
            try { result = backend.buyMeat(1); } catch (Exception e) { error = e; }
            final JSONObject data = result; final Exception failure = error;
            runOnUiThread(() -> { if (failure != null) status.setText("Pembelian gagal: " + failure.getMessage()); else status.setText("Berhasil membeli 1 daging dengan DM."); refreshState(); });
        }, "kic-buy-meat").start();
    }

    private void consumeOne() {
        consumeButton.setEnabled(false); status.setText("Mengurangi 1 daging...");
        new Thread(() -> {
            JSONObject result = null; Exception error = null;
            try { result = backend.consumeMeat(); } catch (Exception e) { error = e; }
            final Exception failure = error;
            runOnUiThread(() -> { if (failure != null) status.setText("Tidak bisa memulai misi: " + failure.getMessage()); else status.setText("1 daging telah digunakan."); refreshState(); });
        }, "kic-consume-meat").start();
    }

    private void updateTimerText() {
        if (currentMeat >= capacity) { timer.setText("Daging penuh"); return; }
        final int show = Math.max(0, secondsToNext);
        timer.setText("Daging berikutnya dalam " + (show / 60) + ":" + String.format(java.util.Locale.ROOT, "%02d", show % 60));
        secondsToNext = Math.max(0, secondsToNext - 1);
        handler.postDelayed(() -> updateTimerText(), 1000L);
    }

    @Override protected void onDestroy() { handler.removeCallbacksAndMessages(null); super.onDestroy(); }
    private int dp(int n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private static LinearLayout.LayoutParams matchWrap() { return new LinearLayout.LayoutParams(-1, -2); }
}
