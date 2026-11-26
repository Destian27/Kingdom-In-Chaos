package com.destian.dtp;

import android.util.Base64;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.security.SecureRandom;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * Klien Supabase Realtime (WebSocket) tanpa library. Sekali pakai: buat baru, start(), lalu stop().
 * Setiap ada perubahan di tabel app_maintenance, listener dipanggil (di thread socket).
 * Setelah tersambung (atau tersambung ulang) listener juga dipanggil sekali untuk sinkron.
 */
final class RealtimeClient {

    interface Listener {
        void onChange();
    }

    interface AccessTokenProvider {
        String get() throws Exception;
    }

    private static final String HOST = "gunzwimrxspbmiducphg.supabase.co";
    private static final long HEARTBEAT_MS = 25000;
    private static final long DEAD_MS = 70000;

    private final Listener listener;
    private final String[] tables;
    private final String filter;
    private final String accessToken;
    private final AccessTokenProvider tokenProvider;
    private final String topic;
    private final SecureRandom rnd = new SecureRandom();
    private final Object wlock = new Object();
    private volatile boolean running;
    private volatile Socket socket;
    private Thread thread;
    private OutputStream out;
    private InputStream in;
    private int ref = 1;

    RealtimeClient(Listener listener) {
        this(listener, new String[] {"app_maintenance"}, null,
                MaintenanceActivity.SUPABASE_ANON_KEY, "realtime:maintenance", null);
    }

    /** Authenticated subscription using a fixed token. */
    RealtimeClient(Listener listener, String[] tables, String filter, String accessToken) {
        this(listener, tables, filter, accessToken, "realtime:player-state", null);
    }

    /** Authenticated subscription that refreshes/revalidates its JWT on reconnect. */
    RealtimeClient(Listener listener, String[] tables, String filter, final SupabaseGameBackend backend) {
        this(listener, tables, filter, backend, "realtime:player-state");
    }

    /** Authenticated subscription with its own channel topic (used for unfiltered public catalogues). */
    RealtimeClient(Listener listener, String[] tables, String filter,
                   final SupabaseGameBackend backend, String channelTopic) {
        this(listener, tables, filter, null, channelTopic, new AccessTokenProvider() {
            @Override public String get() throws Exception {
                backend.currentUser();
                return backend.getAccessTokenForRealtime();
            }
        });
    }

    private RealtimeClient(Listener listener, String[] tables, String filter,
                           String accessToken, String topic, AccessTokenProvider tokenProvider) {
        if (listener == null || tables == null || tables.length == 0) {
            throw new IllegalArgumentException("Listener and tables are required");
        }
        this.listener = listener;
        this.tables = tables.clone();
        this.filter = filter;
        this.accessToken = accessToken == null || accessToken.length() == 0
                ? MaintenanceActivity.SUPABASE_ANON_KEY : accessToken;
        this.tokenProvider = tokenProvider;
        this.topic = topic;
    }

    synchronized void start() {
        if (running || thread != null) {
            return;
        }
        running = true;
        thread = new Thread(new Runnable() {
            @Override
            public void run() {
                loop();
            }
        }, "kic-realtime");
        thread.setDaemon(true);
        thread.start();
    }

    synchronized void stop() {
        running = false;
        closeQuietly();
        if (thread != null) {
            thread.interrupt();
        }
    }

    private void loop() {
        long delay = 1000;
        while (running) {
            long t0 = System.currentTimeMillis();
            try {
                session();
            } catch (Exception e) {
                // sambung ulang di bawah
            }
            closeQuietly();
            if (!running) {
                break;
            }
            if (System.currentTimeMillis() - t0 > 15000) {
                delay = 1000;
            }
            try {
                Thread.sleep(delay);
            } catch (InterruptedException e) {
                break;
            }
            delay = Math.min(delay * 2, 15000);
        }
    }

    private void session() throws Exception {
        Socket raw = new Socket();
        raw.connect(new InetSocketAddress(HOST, 443), 8000);
        SSLSocket s = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault())
                .createSocket(raw, HOST, 443, true);
        socket = s;
        s.setSoTimeout(15000);
        s.startHandshake();
        if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(HOST, s.getSession())) {
            throw new IOException("hostname");
        }
        out = s.getOutputStream();
        in = s.getInputStream();

        byte[] kb = new byte[16];
        rnd.nextBytes(kb);
        String key = Base64.encodeToString(kb, Base64.NO_WRAP);
        String req = "GET /realtime/v1/websocket?apikey=" + MaintenanceActivity.SUPABASE_ANON_KEY
                + "&vsn=1.0.0 HTTP/1.1\r\nHost: " + HOST
                + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key
                + "\r\nSec-WebSocket-Version: 13\r\n\r\n";
        synchronized (wlock) {
            out.write(req.getBytes("UTF-8"));
            out.flush();
        }
        readHandshake();

        String liveToken = tokenProvider == null ? accessToken : tokenProvider.get();
        if (liveToken == null || liveToken.length() == 0) throw new IOException("No Realtime auth token");
        sendText(buildJoinMessage(liveToken));

        long lastBeat = System.currentTimeMillis();
        long lastRx = lastBeat;
        while (running) {
            String m = readMessage();
            long now = System.currentTimeMillis();
            if (m != null) {
                lastRx = now;
                handle(m);
            }
            if (now - lastBeat >= HEARTBEAT_MS) {
                ref++;
                sendText("{\"topic\":\"phoenix\",\"event\":\"heartbeat\",\"payload\":{},\"ref\":\"" + ref + "\"}");
                lastBeat = now;
            }
            if (now - lastRx > DEAD_MS) {
                throw new IOException("dead");
            }
        }
    }

    private void handle(String m) {
        try {
            JSONObject o = new JSONObject(m);
            String ev = o.optString("event");
            if ("postgres_changes".equals(ev) && topic.equals(o.optString("topic"))) {
                listener.onChange();
            } else if ("broadcast".equals(ev) && topic.equals(o.optString("topic"))) {
                JSONObject p = o.optJSONObject("payload");
                String broadcastEvent = p == null ? "" : p.optString("event", "");
                if ("event_store_updated".equals(broadcastEvent)
                        || "player_state_updated".equals(broadcastEvent)
                        || "cave_boss_updated".equals(broadcastEvent)) {
                    listener.onChange();
                }
            } else if ("phx_reply".equals(ev) && topic.equals(o.optString("topic"))) {
                JSONObject p = o.optJSONObject("payload");
                if (p != null && "ok".equals(p.optString("status"))) {
                    listener.onChange();
                }
            }
        } catch (Exception e) {
            // abaikan pesan yang tidak dikenal
        }
    }

    private String buildJoinMessage(String liveToken) throws IOException {
        try {
            org.json.JSONObject config = new org.json.JSONObject();
            config.put("broadcast", new org.json.JSONObject().put("ack", false).put("self", false));
            config.put("presence", new org.json.JSONObject().put("key", ""));
            org.json.JSONArray changes = new org.json.JSONArray();
            for (String table : tables) {
                if (table == null || !table.matches("[a-zA-Z0-9_]+")) {
                    throw new IOException("Invalid Realtime table name");
                }
                org.json.JSONObject change = new org.json.JSONObject();
                change.put("event", "*");
                change.put("schema", "public");
                change.put("table", table);
                if (filter != null && filter.length() > 0) change.put("filter", filter);
                changes.put(change);
            }
            config.put("postgres_changes", changes);
            org.json.JSONObject payload = new org.json.JSONObject();
            payload.put("config", config);
            payload.put("access_token", liveToken);
            org.json.JSONObject frame = new org.json.JSONObject();
            frame.put("topic", topic);
            frame.put("event", "phx_join");
            frame.put("payload", payload);
            frame.put("ref", "1");
            frame.put("join_ref", "1");
            return frame.toString();
        } catch (org.json.JSONException e) {
            throw new IOException("Could not create Supabase Realtime join payload", e);
        }
    }

    private void readHandshake() throws IOException {
        StringBuilder sb = new StringBuilder();
        int b;
        while ((b = in.read()) >= 0) {
            sb.append((char) b);
            int n = sb.length();
            if (n >= 4 && sb.charAt(n - 1) == '\n' && sb.charAt(n - 2) == '\r'
                    && sb.charAt(n - 3) == '\n' && sb.charAt(n - 4) == '\r') {
                break;
            }
            if (n > 8192) {
                throw new IOException("header");
            }
        }
        if (sb.indexOf(" 101") < 0) {
            throw new IOException("handshake");
        }
    }

    private void sendText(String text) throws IOException {
        sendFrame(0x1, text.getBytes("UTF-8"));
    }

    private void sendFrame(int op, byte[] p) throws IOException {
        int n = p.length;
        if (n > 65535) {
            throw new IOException("big");
        }
        byte[] mask = new byte[4];
        rnd.nextBytes(mask);
        int hdr = n < 126 ? 2 : 4;
        byte[] f = new byte[hdr + 4 + n];
        f[0] = (byte) (0x80 | op);
        if (n < 126) {
            f[1] = (byte) (0x80 | n);
        } else {
            f[1] = (byte) (0x80 | 126);
            f[2] = (byte) (n >> 8);
            f[3] = (byte) n;
        }
        System.arraycopy(mask, 0, f, hdr, 4);
        for (int i = 0; i < n; i++) {
            f[hdr + 4 + i] = (byte) (p[i] ^ mask[i & 3]);
        }
        synchronized (wlock) {
            out.write(f);
            out.flush();
        }
    }

    /** Baca satu pesan teks. Mengembalikan null kalau tidak ada data selama 15 detik. */
    private String readMessage() throws IOException {
        ByteArrayOutputStream msg = null;
        while (true) {
            int b0;
            try {
                b0 = in.read();
            } catch (SocketTimeoutException e) {
                if (msg == null) {
                    return null;
                }
                throw e;
            }
            if (b0 < 0) {
                throw new EOFException();
            }
            int b1 = readByte();
            int op = b0 & 0x0F;
            boolean fin = (b0 & 0x80) != 0;
            long len = b1 & 0x7F;
            if (len == 126) {
                len = (readByte() << 8) | readByte();
            } else if (len == 127) {
                len = 0;
                for (int i = 0; i < 8; i++) {
                    len = (len << 8) | readByte();
                }
            }
            if (len > (1 << 20)) {
                throw new IOException("big");
            }
            byte[] mask = null;
            if ((b1 & 0x80) != 0) {
                mask = new byte[4];
                readFully(mask);
            }
            byte[] d = new byte[(int) len];
            readFully(d);
            if (mask != null) {
                for (int i = 0; i < d.length; i++) {
                    d[i] = (byte) (d[i] ^ mask[i & 3]);
                }
            }
            if (op == 8) {
                throw new EOFException("close");
            }
            if (op == 9) {
                sendFrame(0xA, d);
                continue;
            }
            if (op == 10) {
                continue;
            }
            if (msg == null) {
                msg = new ByteArrayOutputStream();
            }
            msg.write(d, 0, d.length);
            if (fin) {
                return msg.toString("UTF-8");
            }
        }
    }

    private int readByte() throws IOException {
        int b = in.read();
        if (b < 0) {
            throw new EOFException();
        }
        return b;
    }

    private void readFully(byte[] buf) throws IOException {
        int off = 0;
        while (off < buf.length) {
            int r = in.read(buf, off, buf.length - off);
            if (r < 0) {
                throw new EOFException();
            }
            off += r;
        }
    }

    private void closeQuietly() {
        Socket s = socket;
        if (s != null) {
            try {
                s.close();
            } catch (IOException e) {
                // abaikan
            }
        }
    }
}
