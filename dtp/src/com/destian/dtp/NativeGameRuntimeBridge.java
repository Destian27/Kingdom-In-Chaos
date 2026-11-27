package com.destian.dtp;

import android.content.Context;
import android.content.SharedPreferences;

/** JNI bridge into the existing Cocos2d-x libgame.so. */
public final class NativeGameRuntimeBridge {
    private static volatile boolean loaded;
    private static volatile String loadFailure = "";
    private static final String PREFS = "kic_barter_economy";
    private static final String KEY_DM_EARNED = "lifetime_dm_earned";

    private NativeGameRuntimeBridge() { }

    private static synchronized boolean ensureLoaded() {
        if (loaded) return true;
        if (loadFailure.length() > 0) return false;
        try {
            System.loadLibrary("kicgamebridge");
            loaded = true;
            return true;
        } catch (Throwable error) {
            loadFailure = error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
            return false;
        }
    }

    /** Reconciles explicitly admin-revised native balances. A target of -1 leaves a wallet untouched. */
    public static String applyEconomy(long coins, long crystals, long goblinCoins, long eventEyes) {
        if (!ensureLoaded()) return "BRIDGE_NOT_LOADED|" + loadFailure;
        try {
            return applyEconomyNative(coins, crystals, goblinCoins, eventEyes);
        } catch (Throwable error) {
            return "BRIDGE_CALL_FAILED|" + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        }
    }

    /** Installs the native barter gate and DM-earned counter after libgame.so is loaded. */
    public static String installEconomyHooks() {
        if (!ensureLoaded()) return "BRIDGE_NOT_LOADED|" + loadFailure;
        try {
            String state = installEconomyHooksNative();
            if (state != null && state.startsWith("OK|")) {
                seedLifetimeDmFromCurrentWallet();
                DtpApp app = DtpApp.getInstance();
                if (app != null) GameOnlineOverlay.refreshBarterStatus();
            }
            return state;
        } catch (Throwable error) {
            return "BRIDGE_CALL_FAILED|" + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        }
    }

    /** Runs one real barter exchange or original in-game reward package. */
    public static String performBarter(int offerId) {
        if (!ensureLoaded()) return "BRIDGE_NOT_LOADED|" + loadFailure;
        try {
            return performBarterNative(offerId);
        } catch (Throwable error) {
            return "BRIDGE_CALL_FAILED|" + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        }
    }

    /**
     * Applies monotonic native-wallet targets from a claimed in-game letter.
     * Targets are persisted by NativeGameRuntimeSync before this is called,
     * making retries after process death safe against duplicate credits.
     */
    public static String applyMailWalletTargets(int coins, int crystals, int goblinCoins, int life) {
        if (!ensureLoaded()) return "BRIDGE_NOT_LOADED|" + loadFailure;
        try {
            return applyWalletTargetsNative(coins, crystals, goblinCoins, life);
        } catch (Throwable error) {
            return "BRIDGE_CALL_FAILED|" + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        }
    }

    /** Reads current in-game wallet values from LevelManager. */
    public static String getWallet() {
        if (!ensureLoaded()) return "BRIDGE_NOT_LOADED|" + loadFailure;
        try {
            return getWalletNative();
        } catch (Throwable error) {
            return "BRIDGE_CALL_FAILED|" + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        }
    }

    /** Starts the cumulative-DM meter from the existing balance once per installation. */
    private static void seedLifetimeDmFromCurrentWallet() {
        DtpApp app = DtpApp.getInstance();
        if (app == null) return;
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (prefs.contains(KEY_DM_EARNED)) return;
        try {
            String wallet = getWalletNative();
            int marker = wallet == null ? -1 : wallet.indexOf("dm=");
            if (marker < 0) return;
            String raw = wallet.substring(marker + 3).trim().split("[;|]", 2)[0].trim();
            long balance = Long.parseLong(raw);
            if (balance < 0L) balance = 0L;
            prefs.edit().putLong(KEY_DM_EARNED, balance).apply();
        } catch (Throwable ignored) { }
    }

    /** Called by the native IncreaseCrystal hook after the actual wallet is increased. */
    static void onCrystalsEarned(int amount) {
        if (amount <= 0) return;
        DtpApp app = DtpApp.getInstance();
        if (app == null) return;
        synchronized (NativeGameRuntimeBridge.class) {
            SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            long current = prefs.getLong(KEY_DM_EARNED, 0L);
            long next = current > Long.MAX_VALUE - amount ? Long.MAX_VALUE : current + amount;
            prefs.edit().putLong(KEY_DM_EARNED, next).apply();
        }
        GameOnlineOverlay.refreshBarterStatus();
    }

    /** Called by the native barter hook; the UI callback only displays a result message. */
    static void onBarterResult(int offerId, int status) {
        GameOnlineOverlay.notifyBarterResult(offerId, status);
    }

    public static long getLifetimeDmEarned(Context context) {
        if (context == null) return 0L;
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getLong(KEY_DM_EARNED, 0L);
    }

    private static native String applyEconomyNative(long coins, long crystals, long goblinCoins, long eventEyes);
    private static native String installEconomyHooksNative();
    private static native String performBarterNative(int offerId);
    private static native String getWalletNative();
    private static native String applyWalletTargetsNative(int coins, int crystals, int goblinCoins, int life);
}
