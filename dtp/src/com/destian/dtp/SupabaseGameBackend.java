package com.destian.dtp;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.net.Uri;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.KeyStore;
import java.security.GeneralSecurityException;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import java.net.URLEncoder;
import java.util.Locale;
import java.security.SecureRandom;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

/**
 * Supabase data/auth adapter for Kingdom in Chaos DTP.
 *
 * Call these methods on a worker thread; they perform synchronous HTTPS I/O.
 * Only the publishable/anon project key is embedded here. NEVER put service_role
 * credentials in an APK. This adapter is a backend client, not a native C++ UI hook.
 */
public final class SupabaseGameBackend {
    private static final String BASE_URL = "https://gunzwimrxspbmiducphg.supabase.co";
    private static final String ANON_KEY =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1bnp3aW1yeHNwYm1pZHVjcGhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU2Njk0NDYsImV4cCI6MjExMTI0NTQ0Nn0.OQn69Q-IZ4k1ZyXc6hk8oBi7vFyOBfWTgRUXuKZqocY";
    private static final String PREFS = "kic_supabase_session_v1";
    private static final String ACCESS = "access_token";
    private static final String REFRESH = "refresh_token";
    private static final int TIMEOUT_MS = 15000;

    private final SharedPreferences prefs;

    public SupabaseGameBackend(Context context) {
        if (context == null) throw new IllegalArgumentException("Context is required");
        prefs = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }


    // v1.0.7: login Google (OAuth/PKCE) dihapus total; pemain masuk lewat nama pengguna + kata sandi (PlayerBackend).

    public JSONObject refreshSession() throws IOException {
        String refresh = readSecret(REFRESH);
        if (isBlank(refresh)) throw new IOException("No saved refresh token; please sign in again.");
        JSONObject payload = new JSONObject();
        try { payload.put("refresh_token", refresh); }
        catch (JSONException e) { throw new IOException("Cannot encode refresh request", e); }
        JSONObject result = request("/auth/v1/token?grant_type=refresh_token", "POST", payload, null, false);
        storeSession(result);
        return result;
    }

    public void signOut() throws IOException {
        String access = readSecret(ACCESS);
        try {
            if (!isBlank(access)) request("/auth/v1/logout", "POST", new JSONObject(), access, false);
        } finally {
            prefs.edit().remove(ACCESS).remove(REFRESH).apply();
        }
    }

    public boolean hasSession() {
        return !isBlank(prefs.getString(ACCESS, null)) || !isBlank(prefs.getString(REFRESH, null));
    }

    public JSONObject currentUser() throws IOException {
        return requestAuthenticated("/auth/v1/user", "GET", null);
    }

    /** Get the current user's profile row through PostgREST after login. */
    public JSONObject getMyProfile() throws IOException {
        JSONObject user = currentUser();
        String uid = user.optString("id", "");
        if (isBlank(uid)) throw new IOException("Supabase Auth did not return a user ID");
        JSONArray rows = requestAuthenticatedArray("/rest/v1/game_profiles?select=user_id,legacy_uid,username,nickname,avatar_id,region,created_at,updated_at&user_id=eq." + enc(uid) + "&limit=1");
        if (rows.length() == 0) throw new IOException("Game profile not found. Check that the SQL migration was applied.");
        try { return rows.getJSONObject(0); }
        catch (JSONException e) { throw new IOException("Invalid profile returned by Supabase", e); }
    }

    /** avatarId selects an avatar bundled in the original game; this is not an image upload. */
    public JSONObject updateProfile(String nickname, int avatarId, String region) throws IOException {
        requireLength(nickname, "nickname", 1, 32);
        if (avatarId < 0) throw new IOException("Avatar ID cannot be negative");
        if (isBlank(region) || region.trim().length() > 16) throw new IOException("Region must contain 1-16 characters");
        JSONObject body = new JSONObject();
        try {
            body.put("p_nickname", nickname.trim());
            body.put("p_avatar_id", avatarId);
            body.put("p_region", region.trim());
        } catch (JSONException e) { throw new IOException("Cannot encode profile request", e); }
        return requestAuthenticatedSingle("/rest/v1/rpc/update_my_game_profile", "POST", body);
    }

    public JSONArray findPlayers(String query, int limit) throws IOException {
        requireLength(query, "search", 2, 80);
        JSONObject body = new JSONObject();
        try { body.put("p_query", query.trim()); body.put("p_limit", clamp(limit, 1, 50)); }
        catch (JSONException e) { throw new IOException("Cannot encode player search", e); }
        return requestAuthenticatedArray("/rest/v1/rpc/find_game_players", "POST", body);
    }

    public JSONObject sendFriendRequest(String targetUserId) throws IOException {
        JSONObject body = uuidArg("p_target_user_id", targetUserId);
        return requestAuthenticatedSingle("/rest/v1/rpc/send_game_friend_request", "POST", body);
    }

    public JSONArray getFriends() throws IOException {
        return requestAuthenticatedArray("/rest/v1/rpc/get_my_game_friends", "POST", new JSONObject());
    }

    public JSONArray getFriendRequests() throws IOException {
        return requestAuthenticatedArray("/rest/v1/rpc/get_my_game_friend_requests", "POST", new JSONObject());
    }

    public JSONObject respondFriendRequest(String requestId, boolean accept) throws IOException {
        JSONObject body = uuidArg("p_request_id", requestId);
        try { body.put("p_accept", accept); }
        catch (JSONException e) { throw new IOException("Cannot encode friend response", e); }
        return requestAuthenticatedSingle("/rest/v1/rpc/respond_game_friend_request", "POST", body);
    }

    public JSONObject removeFriend(String otherUserId) throws IOException {
        return requestAuthenticated("/rest/v1/rpc/remove_game_friend", "POST", uuidArg("p_other_user_id", otherUserId));
    }

    public JSONArray getRankings(int limit) throws IOException {
        String path = "/rest/v1/game_rankings?select=user_id,nickname,avatar_id,level,total_score,pvp_wins,honor_points,updated_at"
                + "&order=total_score.desc,level.desc&limit=" + clamp(limit, 1, 500);
        return requestAuthenticatedArray(path);
    }

    public JSONArray getActiveWorldBossCycles() throws IOException {
        return requestAuthenticatedArray("/rest/v1/rpc/get_active_game_world_boss_cycles", "POST", new JSONObject());
    }

    public JSONArray getMyWorldBossClaims(String cycleId) throws IOException {
        String path = "/rest/v1/game_world_boss_score_claims?select=claim_id,cycle_id,claimed_score,claim_status,submitted_at,reviewed_at,review_note"
                + "&cycle_id=eq." + enc(cycleId) + "&order=submitted_at.desc&limit=50";
        return requestAuthenticatedArray(path);
    }

    public JSONArray getWorldBossRankings(String cycleId, int limit) throws IOException {
        requireLength(cycleId, "cycleId", 1, 80);
        JSONObject body = new JSONObject();
        try { body.put("p_cycle_id", cycleId); body.put("p_limit", clamp(limit, 1, 500)); }
        catch (JSONException e) { throw new IOException("Cannot encode World Boss request", e); }
        return requestAuthenticatedArray("/rest/v1/rpc/get_game_world_boss_rankings", "POST", body);
    }

    /** Stores an UNVERIFIED score claim. It cannot change the official board until server review. */
    public JSONObject submitWorldBossScoreClaim(String cycleId, long score, JSONObject replayPayload) throws IOException {
        requireLength(cycleId, "cycleId", 1, 80);
        if (score < 0) throw new IOException("Score cannot be negative");
        JSONObject payload = replayPayload == null ? new JSONObject() : replayPayload;
        if (payload.toString().length() > 250000) throw new IOException("Replay payload is too large");
        JSONObject body = new JSONObject();
        try {
            body.put("p_cycle_id", cycleId);
            body.put("p_claimed_score", score);
            body.put("p_replay_payload", payload);
        } catch (JSONException e) { throw new IOException("Cannot encode score claim", e); }
        JSONObject result = requestAuthenticated("/rest/v1/rpc/submit_world_boss_score_claim", "POST", body);
        JSONObject wrapped = new JSONObject();
        String claimId = result.optString("value", result.optString("claim_id", ""));
        if (isBlank(claimId)) throw new IOException("Supabase did not return a score claim ID");
        try { wrapped.put("claim_id", claimId); wrapped.put("status", "pending_verification"); }
        catch (JSONException e) { throw new IOException("Cannot wrap score claim", e); }
        return wrapped;
    }

    /** Join or poll the asynchronous PvP queue. This does not itself simulate a battle. */
    public JSONArray joinPvpQueue() throws IOException {
        return requestAuthenticatedArray("/rest/v1/rpc/join_game_pvp_queue", "POST", new JSONObject());
    }

    public JSONObject cancelPvpQueue() throws IOException {
        return requestAuthenticated("/rest/v1/rpc/cancel_game_pvp_queue", "POST", new JSONObject());
    }

    /** Read a PvP match state for a participant; this does not run the native fight. */
    public JSONArray getPvpMatchState(String matchId) throws IOException {
        JSONObject body = uuidArg("p_match_id", matchId);
        return requestAuthenticatedArray("/rest/v1/rpc/get_my_pvp_match_state", "POST", body);
    }

    public JSONArray getPvpHistory(int limit) throws IOException {
        JSONObject body = new JSONObject();
        try { body.put("p_limit", clamp(limit, 1, 200)); }
        catch (JSONException e) { throw new IOException("Cannot encode PvP history request", e); }
        return requestAuthenticatedArray("/rest/v1/rpc/get_my_pvp_history", "POST", body);
    }

    /** Save is sync data only; never trust client-save currency/scores for competitive rewards. */
    public JSONObject saveGame(int saveVersion, JSONObject saveData) throws IOException {
        if (saveVersion < 1) throw new IOException("Save version must be positive");
        if (saveData == null) throw new IOException("Save data is required");
        JSONObject body = new JSONObject();
        try { body.put("p_save_version", saveVersion); body.put("p_save_data", saveData); }
        catch (JSONException e) { throw new IOException("Cannot encode save request", e); }
        return requestAuthenticatedSingle("/rest/v1/rpc/save_my_game_data", "POST", body);
    }

    public JSONArray loadGameSave() throws IOException {
        return requestAuthenticatedArray("/rest/v1/game_player_saves?select=user_id,save_version,save_data,updated_at&limit=1");
    }

    public JSONObject heartbeat(String roomCode) throws IOException {
        JSONObject body = new JSONObject();
        try { if (!isBlank(roomCode)) body.put("p_room_code", roomCode.trim()); }
        catch (JSONException e) { throw new IOException("Cannot encode heartbeat", e); }
        return requestAuthenticated("/rest/v1/rpc/heartbeat_game_presence", "POST", body);
    }

    public JSONObject markOffline() throws IOException {
        return requestAuthenticated("/rest/v1/rpc/set_my_game_presence_offline", "POST", new JSONObject());
    }

    /** Current authenticated server-side profile/economy/ranking/cloud-save snapshot. */
    public JSONObject getMyRuntimeState() throws IOException {
        return requestAuthenticated("/rest/v1/rpc/get_my_game_runtime_state", "POST", new JSONObject());
    }

    /** Current Cave Boss event, evaluated server-side using Asia/Jakarta time. */
    public JSONObject getActiveCaveBoss() throws IOException {
        return requestAuthenticated("/rest/v1/rpc/get_active_cave_boss", "POST", new JSONObject());
    }

    /** Current server-controlled event shop, including this player's separate Event Eyes balance. */
    public JSONObject getActiveEventStore() throws IOException {
        return requestAuthenticated("/rest/v1/rpc/get_active_event_store", "POST", new JSONObject());
    }

    /** Access token for the short-lived Realtime WebSocket subscription only. */
    public String getAccessTokenForRealtime() throws IOException {
        String token = readSecret(ACCESS);
        if (isBlank(token) && !isBlank(readSecret(REFRESH))) {
            refreshSession();
            token = readSecret(ACCESS);
        }
        if (isBlank(token)) throw new IOException("Please log in before subscribing to Realtime");
        return token;
    }

    private JSONObject requestAuthenticated(String path, String method, JSONObject body) throws IOException {
        String token = readSecret(ACCESS);
        if (isBlank(token)) {
            if (!isBlank(readSecret(REFRESH))) {
                refreshSession();
                token = readSecret(ACCESS);
            }
        }
        if (isBlank(token)) throw new IOException("Not logged in to Supabase");
        try {
            return request(path, method, body, token, true);
        } catch (ApiException e) {
            if (e.statusCode == 401 && !isBlank(readSecret(REFRESH))) {
                refreshSession();
                String refreshed = readSecret(ACCESS);
                if (!isBlank(refreshed)) return request(path, method, body, refreshed, true);
            }
            throw e;
        }
    }

    private JSONObject requestAuthenticatedSingle(String path, String method, JSONObject body) throws IOException {
        JSONObject result = requestAuthenticated(path, method, body);
        JSONArray array = result.optJSONArray("__array");
        if (array == null) return result;
        if (array.length() == 0) throw new IOException("Supabase returned no row");
        try { return array.getJSONObject(0); }
        catch (JSONException e) { throw new IOException("Invalid row returned by Supabase", e); }
    }

    private JSONArray requestAuthenticatedArray(String path) throws IOException {
        return toArray(requestAuthenticated(path, "GET", null));
    }

    private JSONArray requestAuthenticatedArray(String path, String method, JSONObject body) throws IOException {
        return toArray(requestAuthenticated(path, method, body));
    }

    private JSONObject request(String path, String method, JSONObject body, String token, boolean authenticated) throws IOException {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(BASE_URL + path);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod(method);
            connection.setConnectTimeout(TIMEOUT_MS);
            connection.setReadTimeout(TIMEOUT_MS);
            connection.setUseCaches(false);
            connection.setRequestProperty("apikey", ANON_KEY);
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("Authorization", "Bearer " + (isBlank(token) ? ANON_KEY : token));
            if (body != null) {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                connection.setRequestProperty("Prefer", "return=representation");
                byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
                connection.setFixedLengthStreamingMode(bytes.length);
                OutputStream out = connection.getOutputStream();
                try { out.write(bytes); } finally { out.close(); }
            }
            int status = connection.getResponseCode();
            InputStream stream = status >= 200 && status < 400 ? connection.getInputStream() : connection.getErrorStream();
            String response = stream == null ? "" : readFully(stream);
            if (status < 200 || status >= 300) {
                throw new ApiException(status, extractError(response, status));
            }
            if (response.trim().isEmpty()) return new JSONObject();
            String trimmed = response.trim();
            if (trimmed.startsWith("[")) {
                JSONObject wrap = new JSONObject();
                wrap.put("__array", new JSONArray(trimmed));
                return wrap;
            }
            if (trimmed.startsWith("{")) return new JSONObject(trimmed);
            JSONObject wrap = new JSONObject();
            Object scalar;
            try {
                scalar = new org.json.JSONTokener(trimmed).nextValue();
            } catch (JSONException ignored) {
                scalar = trimmed;
            }
            wrap.put("value", scalar);
            return wrap;
        } catch (JSONException e) {
            throw new IOException("Invalid JSON received from Supabase", e);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static JSONArray toArray(JSONObject result) throws IOException {
        JSONArray a = result.optJSONArray("__array");
        if (a != null) return a;
        if (result.length() == 0) return new JSONArray();
        throw new IOException("Expected a JSON array from Supabase");
    }

    private void storeSession(JSONObject result) throws IOException {
        String access = result.optString("access_token", "");
        String refresh = result.optString("refresh_token", "");
        if (!isBlank(access)) writeSecret(ACCESS, access);
        if (!isBlank(refresh)) writeSecret(REFRESH, refresh);
    }

    // Encrypt long-lived session tokens with an AES key held by Android Keystore.
    // Only the IV and ciphertext are stored in private SharedPreferences.
    private String readSecret(String name) throws IOException {
        String stored = prefs.getString(name, null);
        if (isBlank(stored)) return null;
        try {
            int dot = stored.indexOf('.');
            if (dot <= 0 || dot >= stored.length() - 1) throw new GeneralSecurityException("Malformed encrypted token");
            byte[] iv = Base64.decode(stored.substring(0, dot), Base64.NO_WRAP);
            byte[] ciphertext = Base64.decode(stored.substring(dot + 1), Base64.NO_WRAP);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateTokenKey(), new GCMParameterSpec(128, iv));
            return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
        } catch (Exception e) {
            prefs.edit().remove(ACCESS).remove(REFRESH).apply();
            throw new IOException("Saved session cannot be decrypted. Please sign in again.", e);
        }
    }

    private void writeSecret(String name, String value) throws IOException {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateTokenKey());
            byte[] iv = cipher.getIV();
            byte[] ciphertext = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
            String encoded = Base64.encodeToString(iv, Base64.NO_WRAP) + "."
                    + Base64.encodeToString(ciphertext, Base64.NO_WRAP);
            prefs.edit().putString(name, encoded).apply();
        } catch (Exception e) {
            throw new IOException("Unable to protect Supabase session token with Android Keystore", e);
        }
    }

    private SecretKey getOrCreateTokenKey() throws Exception {
        final String alias = "kic.dtp.supabase.session.aes.v1";
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (keyStore.containsAlias(alias)) return (SecretKey) keyStore.getKey(alias, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build();
        generator.init(spec);
        return generator.generateKey();
    }

    private static JSONObject uuidArg(String key, String value) throws IOException {
        requireText(value, key);
        // UUIDs are passed to Postgres as strings; server-side argument types validate their format.
        JSONObject body = new JSONObject();
        try { body.put(key, value.trim()); }
        catch (JSONException e) { throw new IOException("Cannot encode request", e); }
        return body;
    }

    private static String readFully(InputStream input) throws IOException {
        InputStreamReader reader = new InputStreamReader(input, StandardCharsets.UTF_8);
        BufferedReader buffered = new BufferedReader(reader);
        StringBuilder out = new StringBuilder();
        String line;
        try { while ((line = buffered.readLine()) != null) out.append(line); }
        finally { buffered.close(); }
        return out.toString();
    }

    private static String extractError(String text, int status) {
        if (text != null && !text.trim().isEmpty()) {
            try {
                JSONObject error = new JSONObject(text);
                String message = error.optString("message", error.optString("msg", ""));
                String details = error.optString("details", "");
                String hint = error.optString("hint", "");
                StringBuilder result = new StringBuilder(message.isEmpty() ? text : message);
                if (!details.isEmpty()) result.append(" — ").append(details);
                if (!hint.isEmpty()) result.append(" ( ").append(hint).append(" )");
                return result.toString();
            } catch (JSONException ignored) { return text; }
        }
        return "Supabase request failed with HTTP " + status;
    }

    private static String enc(String s) throws IOException {
        try { return URLEncoder.encode(s, "UTF-8"); }
        catch (Exception e) { throw new IOException("Cannot encode URL parameter", e); }
    }

    private static int clamp(int value, int min, int max) { return Math.max(min, Math.min(max, value)); }
    private static boolean isBlank(String s) { return s == null || s.trim().isEmpty(); }
    private static void requireText(String s, String field) throws IOException {
        if (isBlank(s)) throw new IOException(field + " is required");
    }
    private static void requireLength(String s, String field, int min, int max) throws IOException {
        requireText(s, field);
        int length = s.trim().length();
        if (length < min || length > max) throw new IOException(field + " must contain " + min + "-" + max + " characters");
    }

    public static final class ApiException extends IOException {
        private static final long serialVersionUID = 1L;
        public final int statusCode;
        ApiException(int statusCode, String message) {
            super(message);
            this.statusCode = statusCode;
        }
    }
}
