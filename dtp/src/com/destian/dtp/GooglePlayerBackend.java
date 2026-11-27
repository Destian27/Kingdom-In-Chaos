package com.destian.dtp;

import android.accounts.Account;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.Intent;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * Direct Google account authentication for Kingdom In Chaos DTP.
 * Google Play Services supplies a Google OAuth access token. The token is
 * verified by the game-player Edge Function through Google's userinfo API.
 * Supabase is used only as the database/function host, never as player Auth.
 */
public final class GooglePlayerBackend {
    private static final String API_URL = "https://gunzwimrxspbmiducphg.supabase.co/functions/v1/google-player";
    private static final String ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1bnp3aW1yeHNwYm1pZHVjcGhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU2Njk0NDYsImV4cCI6MjExMTI0NTQ0Nn0.OQn69Q-IZ4k1ZyXc6hk8oBi7vFyOBfWTgRUXuKZqocY";
    private static final String GOOGLE_SCOPE = "oauth2:openid email profile";
    private static final String PREFS = "kic_google_player_v1";
    private static final String ACCOUNT_NAME = "google_account_name";
    private static final int TIMEOUT_MS = 20000;

    private final Context context;
    private final SharedPreferences prefs;

    public GooglePlayerBackend(Context context) {
        if (context == null) throw new IllegalArgumentException("Context wajib diisi.");
        this.context = context.getApplicationContext();
        this.prefs = this.context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public boolean hasAccount() {
        String value = prefs.getString(ACCOUNT_NAME, null);
        return value != null && !value.trim().isEmpty();
    }

    public String getSavedAccountName() {
        return prefs.getString(ACCOUNT_NAME, "");
    }

    /** Save only the Google account name, never a password or reusable token. */
    public void clearAccount() {
        prefs.edit().remove(ACCOUNT_NAME).apply();
    }

    /** Authenticate a selected Android Google account and register/login the player. */
    public JSONObject loginWithGoogleAccount(String accountName) throws IOException {
        if (accountName == null || accountName.trim().isEmpty()) throw new IOException("Akun Google tidak dipilih.");
        String clean = accountName.trim();
        String token = googleAccessToken(clean);
        JSONObject result = playerRequest("bootstrap", new JSONObject(), token);
        prefs.edit().putString(ACCOUNT_NAME, clean).apply();
        return result;
    }

    public JSONObject completeProfile(String nickname) throws IOException {
        JSONObject body = new JSONObject();
        try { body.put("nickname", nickname == null ? "" : nickname.trim()); }
        catch (JSONException e) { throw new IOException("Tidak dapat menyiapkan profil pemain.", e); }
        return requestSavedAccount("complete_profile", body);
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

    /** Read the authenticated Google player's in-game mailbox. */
    public JSONObject getInbox() throws IOException {
        return requestSavedAccount("get_mail", new JSONObject());
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
        String account = getSavedAccountName();
        if (account.isEmpty()) throw new IOException("Silakan login dengan Google terlebih dahulu.");
        String token = googleAccessToken(account);
        return playerRequest(action, body, token);
    }

    private String googleAccessToken(String accountName) throws IOException {
        try {
            Class<?> authUtil = Class.forName("com.google.android.gms.auth.GoogleAuthUtil");
            Method method = authUtil.getMethod("getToken", Context.class, Account.class, String.class);
            Account account = new Account(accountName, "com.google");
            Object result = method.invoke(null, context, account, GOOGLE_SCOPE);
            if (!(result instanceof String) || ((String) result).trim().isEmpty()) {
                throw new IOException("Google tidak memberikan token akses.");
            }
            return ((String) result).trim();
        } catch (InvocationTargetException e) {
            Throwable cause = e.getCause() == null ? e : e.getCause();
            String className = cause.getClass().getName();
            if (className.endsWith("UserRecoverableAuthException")) {
                try {
                    Object recoverable = cause.getClass().getMethod("getIntent").invoke(cause);
                    if (recoverable instanceof Intent) throw new RecoverableGoogleAuthException((Intent) recoverable);
                } catch (ReflectiveOperationException reflectionError) {
                    throw new IOException("Persetujuan Google diperlukan. Coba login Google kembali.", reflectionError);
                }
            }
            throw new IOException("Google Auth gagal: " + safeMessage(cause), cause);
        } catch (ClassNotFoundException e) {
            throw new IOException("Google Play Services Auth tidak tersedia pada perangkat ini.", e);
        } catch (NoSuchMethodException | IllegalAccessException e) {
            throw new IOException("Google Auth tidak kompatibel dengan versi Google Play Services ini.", e);
        }
    }

    private JSONObject playerRequest(String action, JSONObject payload, String googleAccessToken) throws IOException {
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
            connection.setRequestProperty("Authorization", "Bearer " + googleAccessToken);
            JSONObject request = new JSONObject(payload.toString());
            request.put("action", action);
            byte[] bytes = request.toString().getBytes(StandardCharsets.UTF_8);
            try (OutputStream out = connection.getOutputStream()) { out.write(bytes); }
            int status = connection.getResponseCode();
            InputStream stream = status >= 200 && status < 300 ? connection.getInputStream() : connection.getErrorStream();
            String response = readAll(stream);
            JSONObject json = new JSONObject(response);
            if (status < 200 || status >= 300 || json.optBoolean("ok", true) == false) {
                throw new IOException(json.optString("error", "Permintaan server pemain gagal."));
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

    private static String safeMessage(Throwable error) {
        String value = error == null ? null : error.getMessage();
        return value == null || value.trim().isEmpty() ? "Periksa akun Google dan koneksi internet." : value;
    }

    public static final class RecoverableGoogleAuthException extends IOException {
        private final Intent recoveryIntent;
        RecoverableGoogleAuthException(Intent intent) {
            super("Google membutuhkan persetujuan tambahan.");
            recoveryIntent = intent;
        }
        public Intent getRecoveryIntent() { return recoveryIntent; }
    }
}
