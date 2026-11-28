package com.destian.dtp;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * v1.0.8: jembatan Masuk / Daftar BAWAAN game.
 *
 * Dialog Masuk, Daftar, dan pengisian nama panggilan/avatar milik game (UIPopupLogIn, UIPopupSignUpAccount,
 * UIPopupSignUpInfo) memanggil NetworkManager::logIn / signUp / modifyAccount. Fungsi native itu mengirim
 * permintaan HTTP ke server lama. libgame.so sudah ditambal (tools/patch_v1_0_8_local_auth.py) sehingga
 * tiga permintaan itu menuju http://127.0.0.1:7391/ — server kecil ini. Jawabannya meniru format JSON asli
 * ({"status":..,"region":..,"image":..,"nickname":..}); semua logika game (toast, popup lanjutan, penyimpanan
 * akun) tetap dijalankan kode native game. Kata sandi diteruskan ke Edge Function lewat HTTPS dan TIDAK
 * disimpan oleh kelas ini; hanya token sesi (PlayerBackend) dan data tampilan (nama panggilan, avatar, wilayah).
 *
 * Kode status (pasti dari disassembly NetworkManager::onLogInHttpResponse / onSignupHttpResponse):
 *   Masuk : status >= 0 sukses (nilainya = id akun) | -1 akun tidak ada | -2 kata sandi salah | negatif lain = galat jaringan.
 *   Daftar: status > 0 sukses (id akun) | 0 nama sudah dipakai | negatif = galat jaringan.
 */
public final class LocalAuthServer {
    public static final int PORT = 7391;

    private static final String PROFILE_PREFS = "kic_native_profile_v1";
    private static final long BACKEND_DEADLINE_MS = 17000L; // game menunggu 20 dtk (CCHttpClient timeout)
    private static final int NETWORK_ERROR = -9;
    private static final Pattern HTTP_CODE = Pattern.compile("^\\[HTTP (\\d{3})\\]\\s*(.*)$", Pattern.DOTALL);
    private static final String DEFAULT_REGION = "US";
    private static final int DEFAULT_IMAGE = 1;

    private static LocalAuthServer instance;
    /** Ringkasan (nama+kata sandi) yang sudah terbukti benar di server selama proses ini; hanya di memori. */
    private static volatile String verifiedDigest = "";

    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());

    private LocalAuthServer(Context context) {
        this.context = context.getApplicationContext();
    }

    public static synchronized void start(Context context) {
        if (instance != null || context == null) return;
        instance = new LocalAuthServer(context);
        instance.begin();
    }

    public static void forgetVerifiedPassword() {
        verifiedDigest = "";
    }

    private void begin() {
        Thread acceptor = new Thread(new Runnable() {
            @Override public void run() { acceptLoop(); }
        }, "kic-local-auth");
        acceptor.setDaemon(true);
        acceptor.start();
    }

    private void acceptLoop() {
        ServerSocket server = null;
        for (int attempt = 0; attempt < 20 && server == null; attempt++) {
            try {
                ServerSocket candidate = new ServerSocket();
                candidate.setReuseAddress(true);
                candidate.bind(new InetSocketAddress(InetAddress.getByAddress(new byte[]{127, 0, 0, 1}), PORT), 16);
                server = candidate;
            } catch (IOException busy) {
                try { Thread.sleep(1500L); } catch (InterruptedException stop) { return; }
            }
        }
        if (server == null) return;
        while (!server.isClosed()) {
            try {
                final Socket client = server.accept();
                Thread worker = new Thread(new Runnable() {
                    @Override public void run() { serve(client); }
                }, "kic-local-auth-conn");
                worker.setDaemon(true);
                worker.start();
            } catch (IOException e) {
                if (server.isClosed()) return;
            }
        }
    }

    // ---------------------------------------------------------------- HTTP

    private void serve(Socket socket) {
        try {
            socket.setSoTimeout(8000);
            if (!socket.getInetAddress().isLoopbackAddress()) return;
            String requestLine = readRequestLine(socket.getInputStream());
            byte[] body;
            if (requestLine == null) {
                body = status(NETWORK_ERROR, null).toString().getBytes(StandardCharsets.UTF_8);
            } else {
                String[] parts = requestLine.split(" ");
                String target = parts.length >= 2 ? parts[1] : "/";
                body = handle(target).toString().getBytes(StandardCharsets.UTF_8);
            }
            String head = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n"
                    + "Cache-Control: no-store\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n";
            OutputStream out = socket.getOutputStream();
            out.write(head.getBytes(StandardCharsets.US_ASCII));
            out.write(body);
            out.flush();
        } catch (IOException ignored) {
            // Game akan menampilkan galat jaringan bawaannya.
        } finally {
            try { socket.close(); } catch (IOException ignored) { }
        }
    }

    /** Baca baris permintaan pertama lalu buang sisa header (batas 8 KB). */
    private static String readRequestLine(InputStream in) throws IOException {
        ByteArrayOutputStream head = new ByteArrayOutputStream();
        int previous3 = 0, previous2 = 0, previous1 = 0, current;
        while (head.size() < 8192 && (current = in.read()) != -1) {
            head.write(current);
            if (previous3 == '\r' && previous2 == '\n' && previous1 == '\r' && current == '\n') break;
            previous3 = previous2; previous2 = previous1; previous1 = current;
        }
        String text = new String(head.toByteArray(), StandardCharsets.ISO_8859_1);
        int end = text.indexOf("\r\n");
        if (end < 0) end = text.indexOf('\n');
        return end < 0 ? null : text.substring(0, end).trim();
    }

    private JSONObject handle(String target) {
        String path = target;
        String query = "";
        int mark = target.indexOf('?');
        if (mark >= 0) { path = target.substring(0, mark); query = target.substring(mark + 1); }
        Map<String, String> params = parseQuery(query);
        try {
            if (path.startsWith("/login")) return login(params);
            if (path.startsWith("/signup")) return signup(params);
            if (path.startsWith("/mo")) return modify(params);
        } catch (RuntimeException e) {
            return status(NETWORK_ERROR, null);
        }
        return status(NETWORK_ERROR, null);
    }

    static Map<String, String> parseQuery(String query) {
        Map<String, String> map = new HashMap<>();
        if (query == null || query.isEmpty()) return map;
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            String key = eq < 0 ? pair : pair.substring(0, eq);
            String value = eq < 0 ? "" : pair.substring(eq + 1);
            map.put(key, lenientDecode(value));
        }
        return map;
    }

    /** Game tidak meng-encode nama/kata sandi; %XX hanya didekode bila benar-benar berbentuk %XX. '+' dibiarkan. */
    static String lenientDecode(String value) {
        if (value == null) return "";
        if (value.indexOf('%') < 0) return value;
        byte[] raw = value.getBytes(StandardCharsets.UTF_8);
        ByteArrayOutputStream out = new ByteArrayOutputStream(raw.length);
        for (int i = 0; i < raw.length; i++) {
            if (raw[i] == '%' && i + 2 < raw.length) {
                int hi = Character.digit((char) raw[i + 1], 16);
                int lo = Character.digit((char) raw[i + 2], 16);
                if (hi >= 0 && lo >= 0) { out.write((hi << 4) | lo); i += 2; continue; }
            }
            out.write(raw[i]);
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }

    // ---------------------------------------------------------------- actions

    private JSONObject login(Map<String, String> q) {
        String user = trim(q.get("username"));
        String pass = q.get("password") == null ? "" : q.get("password");
        try {
            JSONObject result = callBackend(true, user, pass);
            return accepted(user, pass, result);
        } catch (IOException e) {
            int code = httpCode(e);
            if (code == 401) return status(-2, null); // pesan server sama untuk nama salah / kata sandi salah
            if (code == 429) return status(-2, httpDetail(e));
            if (code == 0) return status(NETWORK_ERROR, null);
            return status(NETWORK_ERROR, httpDetail(e));
        }
    }

    private JSONObject signup(Map<String, String> q) {
        String user = trim(q.get("username"));
        String pass = q.get("password") == null ? "" : q.get("password");
        try {
            JSONObject result = callBackend(false, user, pass);
            return accepted(user, pass, result);
        } catch (IOException e) {
            String detail = httpDetail(e);
            if (detail.toLowerCase(Locale.ROOT).contains("sudah dipakai")) return status(0, null); // toast_accountDuplicate
            if (httpCode(e) == 0) return status(NETWORK_ERROR, null);
            return status(NETWORK_ERROR, detail);
        }
    }

    /** modify.php: nama panggilan / avatar / wilayah (dan, di game, ubah kata sandi). */
    private JSONObject modify(Map<String, String> q) {
        String user = trim(q.get("username"));
        String pass = q.get("password") == null ? "" : q.get("password");
        PlayerBackend backend = new PlayerBackend(context);
        boolean sameSession = backend.hasAccount() && user.equalsIgnoreCase(backend.getSavedAccountName());
        if (!(sameSession && digest(user, pass).equals(verifiedDigest))) {
            try {
                accepted(user, pass, callBackend(true, user, pass));
            } catch (IOException e) {
                int code = httpCode(e);
                if (code == 401) {
                    // Kata sandi yang dikirim berbeda dari milik akun = percobaan UBAH kata sandi.
                    return status(NETWORK_ERROR, "Mengubah kata sandi belum didukung server DTP. Hubungi admin.");
                }
                return status(NETWORK_ERROR, code == 0 ? null : httpDetail(e));
            }
        }
        SharedPreferences prefs = context.getSharedPreferences(PROFILE_PREFS, Context.MODE_PRIVATE);
        String key = user.toLowerCase(Locale.ROOT);
        String nick = trim(q.get("nickname"));
        String region = trim(q.get("region"));
        int image = parseInt(q.get("image"), -1);
        SharedPreferences.Editor edit = prefs.edit();
        if (!nick.isEmpty()) edit.putString("nick." + key, nick);
        if (!region.isEmpty()) edit.putString("region." + key, region);
        if (image > 0) edit.putInt("image." + key, image);
        edit.apply();
        return profileJson(user, prefs.getInt("uid." + key, uidFromName(user)));
    }

    private JSONObject accepted(String user, String pass, JSONObject result) {
        JSONObject profile = result == null ? null : result.optJSONObject("profile");
        String name = profile == null ? user : profile.optString("nickname", user);
        if (name.isEmpty()) name = user;
        int uid = uidOf(profile, name);
        context.getSharedPreferences(PROFILE_PREFS, Context.MODE_PRIVATE).edit()
                .putInt("uid." + user.toLowerCase(Locale.ROOT), uid).apply();
        verifiedDigest = digest(user, pass);
        GameOnlineOverlay.refreshAccountChip();
        return profileJson(name, uid);
    }

    private JSONObject profileJson(String user, int uid) {
        SharedPreferences prefs = context.getSharedPreferences(PROFILE_PREFS, Context.MODE_PRIVATE);
        String key = user.toLowerCase(Locale.ROOT);
        JSONObject json = new JSONObject();
        try {
            json.put("status", uid);
            json.put("region", prefs.getString("region." + key, DEFAULT_REGION));
            json.put("image", prefs.getInt("image." + key, DEFAULT_IMAGE));
            json.put("nickname", prefs.getString("nick." + key, user));
        } catch (JSONException ignored) { }
        return json;
    }

    private JSONObject status(int code, String message) {
        if (message != null && !message.isEmpty()) toast(message);
        JSONObject json = new JSONObject();
        try { json.put("status", code); } catch (JSONException ignored) { }
        return json;
    }

    // ---------------------------------------------------------------- helpers

    private JSONObject callBackend(final boolean login, final String user, final String pass) throws IOException {
        final PlayerBackend backend = new PlayerBackend(context);
        FutureTask<JSONObject> task = new FutureTask<>(new Callable<JSONObject>() {
            @Override public JSONObject call() throws Exception {
                return login ? backend.login(user, pass) : backend.register(user, pass);
            }
        });
        Thread worker = new Thread(task, "kic-local-auth-backend");
        worker.setDaemon(true);
        worker.start();
        try {
            return task.get(BACKEND_DEADLINE_MS, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            throw new IOException("Server terlalu lama menjawab.");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("Dibatalkan.");
        } catch (ExecutionException e) {
            Throwable cause = e.getCause();
            if (cause instanceof IOException) throw (IOException) cause;
            throw new IOException(String.valueOf(cause), cause);
        }
    }

    private void toast(final String message) {
        main.post(new Runnable() {
            @Override public void run() {
                try { Toast.makeText(context, message, Toast.LENGTH_LONG).show(); } catch (RuntimeException ignored) { }
            }
        });
    }

    private static int httpCode(IOException e) {
        String message = e == null ? null : e.getMessage();
        if (message == null) return 0;
        Matcher m = HTTP_CODE.matcher(message);
        return m.find() ? Integer.parseInt(m.group(1)) : 0;
    }

    private static String httpDetail(IOException e) {
        String message = e == null ? null : e.getMessage();
        if (message == null) return "";
        Matcher m = HTTP_CODE.matcher(message);
        return (m.find() ? m.group(2) : message).trim();
    }

    /** Id angka stabil (>0) untuk game; hanya dipakai game secara lokal. */
    static int uidOf(JSONObject profile, String fallbackName) {
        long value = 0;
        if (profile != null) {
            String digits = profile.optString("player_id", "").replaceAll("[^0-9]", "");
            if (!digits.isEmpty() && digits.length() <= 9) value = Long.parseLong(digits);
            if (value <= 0) value = (profile.optString("player_uuid", "").hashCode() & 0x3fffffff);
        }
        if (value <= 0) value = uidFromName(fallbackName);
        return (int) value;
    }

    static int uidFromName(String name) {
        int v = (name == null ? "" : name.toLowerCase(Locale.ROOT)).hashCode() & 0x3fffffff;
        return v <= 0 ? 1 : v;
    }

    private static String digest(String user, String pass) {
        try {
            MessageDigest sha = MessageDigest.getInstance("SHA-256");
            byte[] out = sha.digest((user.toLowerCase(Locale.ROOT) + "\u0000" + pass).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : out) hex.append(String.format(Locale.ROOT, "%02x", b));
            return hex.toString();
        } catch (java.security.NoSuchAlgorithmException e) {
            return "";
        }
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }

    private static int parseInt(String value, int fallback) {
        try { return Integer.parseInt(value == null ? "" : value.trim()); } catch (NumberFormatException e) { return fallback; }
    }
}
