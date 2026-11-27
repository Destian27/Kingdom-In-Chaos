package com.destian.dtp;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** In-game player mailbox. Rewards are credited only after a server-verified claim. */
public final class GameMailActivity extends Activity {
    private GooglePlayerBackend backend;
    private ExecutorService worker;
    private LinearLayout list;
    private TextView status;
    private Button refresh;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        backend = new GooglePlayerBackend(this);
        worker = Executors.newSingleThreadExecutor();
        buildUi();
        if (!backend.hasAccount()) {
            Toast.makeText(this, "Login Google diperlukan untuk membuka Surat.", Toast.LENGTH_LONG).show();
            startActivity(new android.content.Intent(this, GameAuthActivity.class));
            finish();
            return;
        }
        loadInbox();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(18), dp(18), dp(18), dp(24));
        TextView title = new TextView(this);
        title.setText("SURAT"); title.setTextSize(25); title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        page.addView(title, params());
        TextView note = new TextView(this);
        note.setText("Hadiah dari admin akan masuk ke saldo setelah kamu menekan Klaim. Setiap surat hanya dapat diklaim satu kali.");
        note.setTextSize(13); note.setPadding(0, dp(6), 0, dp(8));
        page.addView(note, params());
        status = new TextView(this); status.setTextSize(13); status.setText("Memuat kotak surat...");
        page.addView(status, params());
        refresh = new Button(this); refresh.setText("Muat Ulang Surat"); refresh.setAllCaps(false);
        refresh.setOnClickListener(v -> loadInbox()); page.addView(refresh, params());
        list = new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams lp = params(); lp.topMargin = dp(10); page.addView(list, lp);
        Button back = new Button(this); back.setText("Kembali"); back.setAllCaps(false);
        back.setOnClickListener(v -> finish()); page.addView(back, params());
        scroll.addView(page); setContentView(scroll);
    }

    private void loadInbox() {
        if (worker == null || worker.isShutdown()) return;
        refresh.setEnabled(false); status.setText("Mengambil Surat...");
        worker.execute(() -> {
            JSONObject result = null; Exception failure = null;
            try { result = backend.getInbox(); } catch (Exception e) { failure = e; }
            final JSONObject data = result; final Exception error = failure;
            runOnUiThread(() -> {
                refresh.setEnabled(true);
                list.removeAllViews();
                if (error != null) { status.setText("Gagal memuat Surat: " + error.getMessage()); return; }
                JSONArray messages = data == null ? new JSONArray() : data.optJSONArray("messages");
                if (messages == null) messages = new JSONArray();
                status.setText(messages.length() + " surat");
                if (messages.length() == 0) {
                    TextView empty = new TextView(this); empty.setText("Belum ada Surat untuk akun ini.");
                    empty.setTextSize(14); list.addView(empty, params()); return;
                }
                for (int i = 0; i < messages.length(); i++) {
                    JSONObject mail = messages.optJSONObject(i);
                    if (mail != null) {
                        String claimedAt = mail.optString("claimed_at", "");
                        if (!claimedAt.isEmpty() && !"null".equals(claimedAt)) {
                            NativeGameRuntimeSync.queueClaimedMail(getApplicationContext(), mail);
                        }
                        addMailCard(mail);
                    }
                }
            });
        });
    }

    private void addMailCard(JSONObject mail) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackgroundColor(0xFFFFF4DF);
        LinearLayout.LayoutParams cp = params(); cp.bottomMargin = dp(10); list.addView(card, cp);
        TextView subject = new TextView(this); subject.setText(mail.optString("subject", "Surat dari Admin"));
        subject.setTextSize(17); subject.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(subject, params());
        TextView body = new TextView(this); body.setText(mail.optString("message", "")); body.setTextSize(14);
        body.setPadding(0, dp(5), 0, dp(5)); card.addView(body, params());
        JSONObject rewards = mail.optJSONObject("reward_config");
        if (rewards == null) rewards = new JSONObject();
        String rewardText = "Hadiah: Koin " + rewards.optLong("coins", 0)
                + " • DM " + rewards.optLong("crystals", 0)
                + " • Goblin " + rewards.optLong("goblin_coins", 0)
                + " • Daging " + rewards.optInt("meat", 0);
        TextView reward = new TextView(this); reward.setText(rewardText); reward.setTextSize(13);
        reward.setTypeface(Typeface.DEFAULT, Typeface.BOLD); card.addView(reward, params());
        TextView date = new TextView(this); date.setText("Dikirim: " + formatDate(mail.optString("created_at", ""))
                + (mail.isNull("expires_at") ? "" : " • Kedaluwarsa: " + formatDate(mail.optString("expires_at"))));
        date.setTextSize(11); card.addView(date, params());
        boolean claimed = !mail.isNull("claimed_at") && !mail.optString("claimed_at", "").isEmpty();
        Button claim = new Button(this); claim.setAllCaps(false);
        claim.setText(claimed ? "Sudah Diklaim" : "Klaim Hadiah"); claim.setEnabled(!claimed);
        card.addView(claim, params());
        if (!claimed) claim.setOnClickListener(v -> claim(mail.optString("mail_id", ""), claim));
    }

    private void claim(String id, Button button) {
        button.setEnabled(false); button.setText("Memproses...");
        worker.execute(() -> {
            JSONObject result = null; Exception failure = null;
            try {
                result = backend.claimMail(id);
                JSONObject claimedMail = result == null ? null : result.optJSONObject("mail");
                if (claimedMail != null) {
                    NativeGameRuntimeSync.queueClaimedMail(getApplicationContext(), claimedMail);
                }
            } catch (Exception e) { failure = e; }
            final JSONObject data = result; final Exception error = failure;
            runOnUiThread(() -> {
                if (error != null) {
                    button.setEnabled(true); button.setText("Klaim Hadiah");
                    new AlertDialog.Builder(this).setTitle("Klaim gagal").setMessage(error.getMessage())
                            .setPositiveButton("OK", null).show();
                    return;
                }
                JSONObject state = data == null ? null : data.optJSONObject("state");
                JSONObject economy = state == null ? null : state.optJSONObject("economy");
                String summary = economy == null ? "Hadiah berhasil diklaim." :
                        "Koin: " + economy.optLong("coins") + "\nDM: " + economy.optLong("crystals")
                                + "\nDaging: " + economy.optInt("meat");
                new AlertDialog.Builder(this).setTitle("Hadiah berhasil diklaim")
                        .setMessage(summary).setPositiveButton("OK", (d, w) -> loadInbox()).show();
            });
        });
    }

    private String formatDate(String value) {
        if (value == null || value.isEmpty()) return "-";
        try {
            String normalized = value.replace("Z", "+0000");
            if (normalized.matches(".*[+-]\\d{2}:\\d{2}$")) normalized = normalized.substring(0, normalized.length() - 3) + normalized.substring(normalized.length() - 2);
            SimpleDateFormat iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US);
            Date date = iso.parse(normalized);
            if (date == null) return value;
            return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(date);
        } catch (Exception ignored) { return value; }
    }
    private LinearLayout.LayoutParams params() {
        return new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }
    private int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density + 0.5f); }
    @Override protected void onDestroy() {
        if (worker != null) worker.shutdownNow();
        super.onDestroy();
    }
}
