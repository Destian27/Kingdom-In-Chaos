package com.destian.dtp;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * v1.0.7: login pemain memakai Nama Pengguna + Kata Sandi (tanpa Google).
 * Server (Edge Function) memeriksa kata sandi (hash PBKDF2) lalu memberi token sesi bertanda tangan.
 * Token itu disimpan di perangkat dan dikirim sebagai Bearer pada setiap permintaan berikutnya.
 * Supabase hanya dipakai sebagai host database/function, bukan Auth pemain.
 */
public final class PlayerBackend {
    private static final String API_URL = "https://gunzwimrxspbmiducphg.supabase.co/functions/v1/google-player";
    private static final String ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1bnp3aW1yeHNwYm1pZHVjcGhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU2Njk0NDYsImV4cCI6MjExMTI0NTQ0Nn0.OQn69Q-IZ4k1ZyXc6hk8oBi7vFyOBfWTgRUXuKZqocY";
    private static final String PREFS = "kic_player_session_v1";
    private static final String KEY_TOKEN = "session_token";
    private static final String KEY_NAME = "player_name";
    private static final int TIMEOUT_MS = 20000;

    private final Context context;
    private final SharedPreferences prefs;

    public PlayerBackend(Context context) {
        if (context == null) throw new IllegalArgumentException("Context wajib diisi.");
        this.context = context.getApplicationContext();
        this.prefs = this.context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public boolean hasAccount() {
        String value = prefs.getString(KEY_TOKEN, null);
        return value != null && !value.trim().isEmpty();
    }

    /** Nama pengguna akun yang sedang masuk (untuk tampilan saja). */
    public String getSavedAccountName() {
        return prefs.getString(KEY_NAME, "");
    }

    /** Keluar: hapus token sesi dari perangkat. Kata sandi tidak pernah disimpan di perangkat. */
    public void clearAccount() {
        prefs.edit().remove(KEY_TOKEN).remove(KEY_NAME).apply();
    }

    /** v1.0.8: sama dengan clearAccount() tetapi sinkron (commit) agar tidak hilang bila proses langsung dimatikan. */
    public void clearAccountNow() {
        prefs.edit().remove(KEY_TOKEN).remove(KEY_NAME).commit();
    }

    /** Daftar akun baru: nama pengguna + kata sandi (4-16). Server menyimpan kata sandi hanya sebagai hash. */
    public JSONObject register(String nickname, String password) throws IOException {
        return authenticate("register", nickname, password);
    }

    /** Masuk ke akun yang sudah terdaftar. */
    public JSONObject login(String nickname, String password) throws IOException {
        return authenticate("login", nickname, password);
    }

    private JSONObject authenticate(String action, String nickname, String password) throws IOException {
        JSONObject body = new JSONObject();
        try {
            body.put("nickname", nickname == null ? "" : nickname.trim());
            body.put("password", password == null ? "" : password);
        } catch (JSONException e) { throw new IOException("Tidak dapat menyiapkan data akun.", e); }
        JSONObject result = playerRequest(action, body, ANON_KEY);
        String token = result.optString("token", "");
        if (token.isEmpty()) throw new IOException("Server tidak mengirim token sesi.");
        JSONObject profile = result.optJSONObject("profile");
        String name = profile == null ? "" : profile.optString("nickname", "");
        if (name.isEmpty() && nickname != null) name = nickname.trim();
        prefs.edit().putString(KEY_TOKEN, token).putString(KEY_NAME, name).apply();
        return result;
    }

    public JSONObject getState() throws IOException {
        return requestSavedAccount("get_state", new JSONObject());
    }

    public JSONObject buyMeat(int amount) throws IOException {
        JSONObject body = new JSONObject();
        try { body.put("amount", amount); }
        catch (JSONException e) { throw new IOException("Tidak dapat menyiapkan pembelian daging.", e); }
        return requestSavedAccount("buy_meat", body);
    }

    public JSONObject consumeMeat() throws IOException {
        return requestSavedAccount("consume_meat", new JSONObject());
    }

    public JSONObject redeemGiftCode(String code) throws IOException {
        JSONObject body = new JSONObject();
        try { body.put("code", code == null ? "" : code.trim()); }
        catch (JSONException e) { throw new IOException("Tidak dapat menyiapkan kode hadiah.", e); }
        return requestSavedAccount("redeem_code", body);
    }

    /** v17.14.19: klaim kode hadiah milik akun ini yang hadiahnya perlu dimasukkan ke saldo native. */
    public JSONObject getCodeClaims() throws IOException {
        return requestSavedAccount("get_code_claims", new JSONObject());
    }

    /**
     * v17.14.20: hadiah dari admin (surat/hadiah langsung) diklaim otomatis oleh server, lalu daftar
     * semua klaim (surat + kode hadiah) dikembalikan agar APK memasukkannya ke saldo native.
     */
    public JSONObject pullRewards() throws IOException {
        return requestSavedAccount("pull_rewards", new JSONObject());
    }

    /** Uploads a read-only observation of the current native game wallet. */
    public JSONObject syncNativeWallet(int coins, int crystals, int goblinCoins, int meat) throws IOException {
        JSONObject body = new JSONObject();
        try {
            body.put("coins", coins);
            body.put("crystals", crystals);
            body.put("goblin_coins", goblinCoins);
            body.put("meat", meat);
        } catch (JSONException e) {
            throw new IOException("Tidak dapat menyiapkan sinkronisasi saldo game.", e);
        }
        return requestSavedAccount("sync_native_wallet", body);
    }

    /** Read the authenticated player's in-game mailbox. */
    public JSONObject getInbox() throws IOException {
        return requestSavedAccount("get_mail", new JSONObject());
    }

    /**
     * v17.14.17: Boss Gua aktif dari server. Pemain tidak punya sesi Supabase Auth,
     * jadi SupabaseGameBackend.getActiveCaveBoss() tidak bisa dipakai; jalur ini lewat Edge Function.
     */
    public JSONObject getCaveBoss() throws IOException {
        return requestSavedAccount("get_cave_boss", new JSONObject());
    }

    /** v17.14.17: katalog + jadwal Event Shop dari server untuk pemain (termasuk saldo Event Eyes). */
    public JSONObject getEventStore() throws IOException {
        return requestSavedAccount("get_event_store", new JSONObject());
    }

    /** Claim a single mail item. The server atomically credits the wallet once. */
    public JSONObject claimMail(String mailId) throws IOException {
        if (mailId == null || !mailId.trim().matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")) {
            throw new IOException("ID surat tidak valid.");
        }
        JSONObject body = new JSONObject();
        try { body.put("mail_id", mailId.trim()); }
        catch (JSONException e) { throw new IOException("Tidak dapat menyiapkan klaim surat.", e); }
        return requestSavedAccount("claim_mail", body);
    }

    private JSONObject requestSavedAccount(String action, JSONObject body) throws IOException {
        String token = prefs.getString(KEY_TOKEN, "");
        if (token == null || token.trim().isEmpty()) throw new IOException("Silakan masuk dengan akun terlebih dahulu.");
        try {
            return playerRequest(action, body, token.trim());
        } catch (IOException e) {
            String message = e.getMessage();
            // Token ditolak server (kedaluwarsa/tidak valid): hapus agar pemain diminta masuk lagi.
            if (message != null && message.startsWith("[HTTP 401]")) clearAccount();
            throw e;
        }
    }

    private JSONObject playerRequest(String action, JSONObject payload, String bearerToken) throws IOException {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(API_URL);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(TIMEOUT_MS);
            connection.setReadTimeout(TIMEOUT_MS);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setRequestProperty("apikey", ANON_KEY);
            connection.setRequestProperty("Authorization", "Bearer " + bearerToken);
            JSONObject request = new JSONObject(payload.toString());
            request.put("action", action);
            byte[] bytes = request.toString().getBytes(StandardCharsets.UTF_8);
            try (OutputStream out = connection.getOutputStream()) { out.write(bytes); }
            int status = connection.getResponseCode();
            InputStream stream = status >= 200 && status < 300 ? connection.getInputStream() : connection.getErrorStream();
            String response = readAll(stream);
            JSONObject json;
            try { json = new JSONObject(response); }
            catch (JSONException notJson) {
                throw new IOException("Server pemain membalas HTTP " + status + " (bukan JSON).", notJson);
            }
            if (status < 200 || status >= 300 || json.optBoolean("ok", true) == false) {
                // v17.14.16: tampilkan pesan asli. Gateway Supabase memakai "message"/"msg", function memakai "error".
                String detail = json.optString("error", "");
                if (detail.isEmpty()) detail = json.optString("message", "");
                if (detail.isEmpty()) detail = json.optString("msg", "");
                if (detail.isEmpty()) detail = "Permintaan server pemain gagal.";
                // v1.0.9: function google-player di Supabase masih versi Google lama (belum diganti v1.0.9).
                String lower = detail.toLowerCase(java.util.Locale.ROOT);
                if (lower.contains("google id token") || lower.contains("google web oauth")
                        || lower.contains("aksi pemain tidak dikenal")) {
                    detail = "Server belum diperbarui: ganti kode function google-player di Supabase dengan versi v1.0.9, lalu coba lagi.";
                }
                throw new IOException("[HTTP " + status + "] " + detail);
            }
            JSONObject data = json.optJSONObject("data");
            return data == null ? json : data;
        } catch (JSONException e) {
            throw new IOException("Jawaban server pemain tidak valid.", e);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String readAll(InputStream input) throws IOException {
        if (input == null) return "{}";
        try (InputStream in = input; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
