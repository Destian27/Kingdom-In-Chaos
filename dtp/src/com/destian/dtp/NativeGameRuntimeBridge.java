package com.destian.dtp;

/**
 * Narrow JNI bridge into the existing Cocos2d-x libgame.so.
 * Calls are made only from the game's GL thread by NativeGameRuntimeSync.
 */
public final class NativeGameRuntimeBridge {
    private static volatile boolean loaded;
    private static volatile String loadFailure = "";

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

    /**
     * Reconciles only explicitly admin-revised native balances. A target of -1
     * leaves that local wallet untouched. Event Eyes uses the game's original
     * FestivalActivityScorePoint key (UserDataType 0x85). Returns OK only after native getters confirm.
     */
    public static String applyEconomy(long coins, long crystals, long goblinCoins, long eventEyes) {
        if (!ensureLoaded()) return "BRIDGE_NOT_LOADED|" + loadFailure;
        try {
            return applyEconomyNative(coins, crystals, goblinCoins, eventEyes);
        } catch (Throwable error) {
            return "BRIDGE_CALL_FAILED|" + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        }
    }

    private static native String applyEconomyNative(long coins, long crystals, long goblinCoins, long eventEyes);
}
