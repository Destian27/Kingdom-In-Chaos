package com.destian.dtp;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.GridLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.NumberFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Server-controlled Event Shop screen shown above the original Cocos2d-x game.
 * The catalogue and Event Eyes balance are live Supabase data. This screen is
 * deliberately display-only until native inventory delivery is verified.
 */
public final class GameEventStoreActivity extends Activity {
    private static final long EVENT_STORE_POLL_MS = 1000L;
    private final Handler main = new Handler(Looper.getMainLooper());
    private ExecutorService io;
    private RealtimeClient realtime;
    private LinearLayout root;
    private LinearLayout header;
    private TextView titleView;
    private TextView countdownView;
    private TextView balanceView;
    private TextView expiryView;
    private TextView messageView;
    private GridLayout itemGrid;
    private long refreshAtMs;
    private int refreshMinutes = 120;
    private boolean destroyed;
    private volatile boolean loadBusy;
    private volatile boolean loadAgain;

    private final Runnable statePoll = new Runnable() {
        @Override public void run() {
            if (destroyed) return;
            loadStore();
            main.postDelayed(this, EVENT_STORE_POLL_MS);
        }
    };

    private final Runnable clockTick = new Runnable() {
        @Override public void run() {
            if (destroyed) return;
            long left = Math.max(0L, refreshAtMs - System.currentTimeMillis());
            long seconds = left / 1000L;
            countdownView.setText(String.format(Locale.ROOT, "REFRESH IN: %02d:%02d:%02d",
                    seconds / 3600L, (seconds / 60L) % 60L, seconds % 60L));
            if (left <= 0L) {
                // Retry server refresh on the one-second fallback cadence if the refresh boundary was reached.
                refreshAtMs = System.currentTimeMillis() + EVENT_STORE_POLL_MS;
                loadStore();
            }
            main.postDelayed(this, 1000L);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        io = Executors.newFixedThreadPool(3);
        buildShell();
        loadStore();
        startRealtime();
        main.postDelayed(statePoll, EVENT_STORE_POLL_MS);
    }

    private void buildShell() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(8), dp(12), dp(8));
        root.setBackgroundColor(Color.rgb(67, 48, 37));

        header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setPadding(dp(8), dp(6), dp(8), dp(6));
        header.setBackground(round(0xFF9D1838, 0xFF6C1028, dp(8)));

        Button back = new Button(this);
        back.setText("‹");
        back.setTextSize(28f);
        back.setTextColor(Color.WHITE);
        back.setAllCaps(false);
        back.setPadding(0, 0, 0, 0);
        back.setBackground(round(0xFF6D2631, 0xFF441821, dp(8)));
        back.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });
        header.addView(back, new LinearLayout.LayoutParams(dp(54), dp(44)));

        LinearLayout titleColumn = new LinearLayout(this);
        titleColumn.setOrientation(LinearLayout.VERTICAL);
        titleColumn.setPadding(dp(12), 0, dp(8), 0);
        titleView = text("EVENT SHOP", 18, Color.WHITE, true);
        countdownView = text("REFRESH IN: --:--:--", 13, 0xFFFFE7D2, true);
        titleColumn.addView(titleView, matchWrap());
        titleColumn.addView(countdownView, matchWrap());
        header.addView(titleColumn, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        LinearLayout balanceBox = new LinearLayout(this);
        balanceBox.setGravity(Gravity.CENTER_VERTICAL);
        balanceBox.setPadding(dp(8), dp(4), dp(10), dp(4));
        balanceBox.setBackground(round(0xFF28231F, 0xFF171411, dp(8)));
        ImageView eye = eyeIcon(dp(34));
        balanceBox.addView(eye, new LinearLayout.LayoutParams(dp(34), dp(34)));
        balanceView = text("0", 19, Color.WHITE, true);
        balanceView.setPadding(dp(7), 0, dp(3), 0);
        balanceBox.addView(balanceView, wrapWrap());
        header.addView(balanceBox, wrapWrap());
        root.addView(header, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(60)));

        expiryView = text("Jadwal event belum dimuat", 12, 0xFFFFE7D2, false);
        expiryView.setPadding(dp(4), dp(6), dp(4), dp(6));
        root.addView(expiryView, matchWrap());

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackground(round(0xFF2A2827, 0xFF77716B, dp(10)));
        itemGrid = new GridLayout(this);
        itemGrid.setColumnCount(4);
        itemGrid.setUseDefaultMargins(false);
        itemGrid.setPadding(dp(8), dp(8), dp(8), dp(8));
        scroll.addView(itemGrid, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        messageView = text("Menghubungkan ke toko event...", 13, 0xFFFFE7D2, false);
        messageView.setPadding(dp(4), dp(5), dp(4), dp(2));
        root.addView(messageView, matchWrap());
        setContentView(root);
    }

    /** Push updates refresh the catalogue immediately; polling remains a reconnect/time-window fallback. */
    private void startRealtime() {
        if (io == null || io.isShutdown()) return;
        io.execute(new Runnable() {
            @Override public void run() {
                final SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                try {
                    if (!backend.hasSession()) return;
                    backend.currentUser();
                    backend.getAccessTokenForRealtime();
                    final RealtimeClient candidate = new RealtimeClient(new RealtimeClient.Listener() {
                        @Override public void onChange() { loadStore(); }
                    }, new String[] {"game_event_store_config", "game_event_store_items"}, null,
                            backend, "realtime:event-store");
                    main.post(new Runnable() {
                        @Override public void run() {
                            if (!destroyed) {
                                realtime = candidate;
                                candidate.start();
                            } else {
                                candidate.stop();
                            }
                        }
                    });
                } catch (Exception error) {
                    // Polling continues when the live channel cannot be established.
                }
            }
        });
    }

    private void loadStore() {
        // RealtimeClient invokes listeners from its socket thread; all View access
        // must be marshalled onto Android's main thread before starting the fetch.
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post(new Runnable() {
                @Override public void run() { loadStore(); }
            });
            return;
        }
        if (destroyed || io == null || io.isShutdown()) return;
        if (loadBusy) {
            loadAgain = true;
            return;
        }
        loadBusy = true;
        loadAgain = false;
        messageView.setText("Memuat data toko dari server...");
        io.execute(new Runnable() {
            @Override public void run() {
                try {
                    SupabaseGameBackend backend = new SupabaseGameBackend(getApplicationContext());
                    final JSONObject state;
                    if (backend.hasSession()) {
                        state = backend.getActiveEventStore();
                    } else {
                        // v17.14.17: pemain login Google langsung -> ambil katalog lewat Edge Function google-player.
                        GooglePlayerBackend google = new GooglePlayerBackend(getApplicationContext());
                        if (!google.hasAccount()) throw new IllegalStateException("Login melalui tombol ONLINE di game terlebih dahulu.");
                        state = google.getEventStore();
                    }
                    main.post(new Runnable() {
                        @Override public void run() {
                            loadBusy = false;
                            if (!destroyed) renderStore(state);
                            if (!destroyed && loadAgain) { loadAgain = false; loadStore(); }
                        }
                    });
                } catch (final Exception error) {
                    main.post(new Runnable() {
                        @Override public void run() {
                            loadBusy = false;
                            if (!destroyed) {
                                itemGrid.removeAllViews();
                                messageView.setText("Toko tidak dapat dimuat: " + safeMessage(error));
                                Toast.makeText(GameEventStoreActivity.this, "Gagal memuat Event Shop", Toast.LENGTH_SHORT).show();
                                if (loadAgain) { loadAgain = false; loadStore(); }
                            }
                        }
                    });
                }
            }
        });
    }

    private void renderStore(JSONObject state) {
        boolean active = state.optBoolean("active", false);
        long eyes = Math.max(0L, state.optLong("event_eyes", 0L));
        balanceView.setText(NumberFormat.getIntegerInstance(new Locale("id", "ID")).format(eyes));
        if (!active) {
            main.removeCallbacks(clockTick);
            titleView.setText("EVENT SHOP TIDAK AKTIF");
            expiryView.setText("Event belum berjalan atau sudah berakhir. Admin dapat mengaktifkan dan menjadwalkan ulang dari panel admin.");
            countdownView.setText("EVENT OFFLINE");
            itemGrid.removeAllViews();
            messageView.setText("Belum ada katalog yang ditampilkan.");
            return;
        }

        titleView.setText(state.optString("title", "EVENT SHOP"));
        refreshMinutes = Math.max(1, state.optInt("refresh_minutes", 120));
        long serverNow = parseIsoMillis(state.optString("server_now", ""));
        long serverRefreshAt = parseIsoMillis(state.optString("refresh_at", ""));
        if (serverNow > 0L && serverRefreshAt > 0L) {
            refreshAtMs = System.currentTimeMillis() + Math.max(0L, serverRefreshAt - serverNow);
        } else {
            refreshAtMs = System.currentTimeMillis() + refreshMinutes * 60000L;
        }
        String endLabel = formatIso(state.optString("ends_at", ""));
        String banner = state.optString("banner_text", "").trim();
        expiryView.setText((banner.length() == 0 ? "" : banner + "  •  ")
                + "Berakhir: " + (endLabel.length() == 0 ? state.optString("ends_at", "-") : endLabel)
                + " WIB  •  " + state.optString("recurrence", "once"));

        JSONArray items = state.optJSONArray("items");
        itemGrid.removeAllViews();
        int count = items == null ? 0 : items.length();
        for (int i = 0; i < count; i++) {
            JSONObject item = items.optJSONObject(i);
            if (item != null) addItemCard(item, i);
        }
        messageView.setText(count == 0
                ? "Event aktif, tetapi admin belum menambahkan item."
                : count + " item dari katalog server. Harga menggunakan Mata Event. Pembelian native belum aktif.");
        main.removeCallbacks(clockTick);
        main.post(clockTick);
    }

    private void addItemCard(JSONObject item, int index) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setGravity(Gravity.CENTER_HORIZONTAL);
        card.setPadding(dp(8), dp(8), dp(8), dp(8));
        card.setBackground(round(0xFFD8BC91, 0xFF876A48, dp(6)));
        GridLayout.LayoutParams params = new GridLayout.LayoutParams(
                GridLayout.spec(GridLayout.UNDEFINED, 1f), GridLayout.spec(GridLayout.UNDEFINED, 1f));
        params.width = 0;
        params.height = dp(178);
        params.setMargins(dp(5), dp(5), dp(5), dp(5));
        itemGrid.addView(card, params);

        TextView name = text(item.optString("item_name", "Item"), 13, 0xFF2F2117, true);
        name.setGravity(Gravity.CENTER);
        name.setMaxLines(2);
        card.addView(name, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(38)));

        ImageView image = new ImageView(this);
        image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        image.setBackground(round(0xFF3A2B27, 0xFF7E342A, dp(6)));
        LinearLayout.LayoutParams imageParams = new LinearLayout.LayoutParams(dp(82), dp(72));
        imageParams.gravity = Gravity.CENTER_HORIZONTAL;
        imageParams.topMargin = dp(4);
        imageParams.bottomMargin = dp(5);
        card.addView(image, imageParams);
        String imageUrl = item.optString("image_url", "");
        if (imageUrl.startsWith("https://")) loadRemoteImage(imageUrl, image);
        else image.setImageResource(android.R.drawable.ic_menu_gallery);

        TextView description = text(item.optString("description", ""), 10, 0xFF5C4938, false);
        description.setGravity(Gravity.CENTER);
        description.setMaxLines(1);
        card.addView(description, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(19)));

        LinearLayout price = new LinearLayout(this);
        price.setGravity(Gravity.CENTER_VERTICAL);
        price.setPadding(dp(4), dp(2), dp(4), dp(2));
        price.setBackground(round(0xFFB48B5E, 0xFF9A744D, dp(5)));
        ImageView eye = eyeIcon(dp(24));
        price.addView(eye, new LinearLayout.LayoutParams(dp(24), dp(24)));
        TextView amount = text(NumberFormat.getIntegerInstance(new Locale("id", "ID")).format(item.optLong("price_eyes", 0L)),
                16, Color.WHITE, true);
        amount.setPadding(dp(6), 0, 0, 0);
        price.addView(amount, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        LinearLayout.LayoutParams priceParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(32));
        priceParams.topMargin = dp(4);
        card.addView(price, priceParams);
    }

    private void loadRemoteImage(final String imageUrl, final ImageView target) {
        io.execute(new Runnable() {
            @Override public void run() {
                HttpURLConnection connection = null;
                try {
                    URL url = new URL(imageUrl);
                    connection = (HttpURLConnection) url.openConnection();
                    connection.setConnectTimeout(7000);
                    connection.setReadTimeout(7000);
                    connection.setInstanceFollowRedirects(true);
                    connection.connect();
                    if (connection.getResponseCode() != 200) return;
                    InputStream stream = connection.getInputStream();
                    final Bitmap bitmap;
                    try { bitmap = BitmapFactory.decodeStream(stream); }
                    finally { stream.close(); }
                    if (bitmap == null) return;
                    main.post(new Runnable() {
                        @Override public void run() { if (!destroyed) target.setImageBitmap(bitmap); }
                    });
                } catch (Exception ignored) {
                    // Keep the placeholder image when an optional item icon cannot load.
                } finally { if (connection != null) connection.disconnect(); }
            }
        });
    }

    private ImageView eyeIcon(int size) {
        ImageView image = new ImageView(this);
        image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        try {
            InputStream stream = getAssets().open("dtp/event_eye_currency.png");
            try { image.setImageBitmap(BitmapFactory.decodeStream(stream)); }
            finally { stream.close(); }
        } catch (Exception ignored) {
            image.setImageResource(android.R.drawable.presence_online);
        }
        return image;
    }

    private long parseIsoMillis(String value) {
        if (value == null || value.length() == 0) return 0L;
        String[] patterns = new String[] {
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"
        };
        for (String pattern : patterns) {
            try {
                SimpleDateFormat parser = new SimpleDateFormat(pattern, Locale.US);
                parser.setTimeZone(TimeZone.getTimeZone("UTC"));
                Date date = parser.parse(value);
                if (date != null) return date.getTime();
            } catch (Exception ignored) { }
        }
        return 0L;
    }

    private String formatIso(String value) {
        if (value == null || value.length() == 0) return "";
        String[] patterns = new String[] {
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"
        };
        for (String pattern : patterns) {
            try {
                SimpleDateFormat parser = new SimpleDateFormat(pattern, Locale.US);
                parser.setTimeZone(TimeZone.getTimeZone("UTC"));
                Date date = parser.parse(value);
                if (date != null) {
                    SimpleDateFormat display = new SimpleDateFormat("dd MMM yyyy HH:mm", new Locale("id", "ID"));
                    display.setTimeZone(TimeZone.getTimeZone("Asia/Jakarta"));
                    return display.format(date);
                }
            } catch (Exception ignored) { }
        }
        return value;
    }

    private GradientDrawable round(int fill, int stroke, int radius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setCornerRadius(radius);
        drawable.setStroke(dp(1), stroke);
        return drawable;
    }
    private TextView text(String value, float size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }
    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }
    private LinearLayout.LayoutParams wrapWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }
    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
    private String safeMessage(Exception error) {
        String message = error.getMessage();
        return message == null || message.trim().length() == 0 ? error.getClass().getSimpleName() : message;
    }

    @Override protected void onDestroy() {
        destroyed = true;
        if (realtime != null) { realtime.stop(); realtime = null; }
        main.removeCallbacks(clockTick);
        if (io != null) io.shutdownNow();
        super.onDestroy();
    }
}
