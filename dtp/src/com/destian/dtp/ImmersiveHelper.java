package com.destian.dtp;

import android.app.Activity;
import android.graphics.Color;
import android.os.Build;
import android.view.DisplayCutout;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

/**
 * v17.14.14 — tampilan layar penuh sungguhan: status bar dan tombol navigasi
 * disembunyikan, area poni/kamera ikut terisi, dan dipulihkan setiap kali jendela fokus.
 */
public final class ImmersiveHelper {
    private ImmersiveHelper() { }

    @SuppressWarnings("deprecation")
    public static void apply(Activity activity) {
        if (activity == null) return;
        try {
            Window window = activity.getWindow();
            if (window == null) return;
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
            if (Build.VERSION.SDK_INT >= 28) {
                WindowManager.LayoutParams lp = window.getAttributes();
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
                window.setAttributes(lp);
            }
            window.setStatusBarColor(Color.TRANSPARENT);
            window.setNavigationBarColor(Color.TRANSPARENT);
            View decor = window.getDecorView();
            decor.setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
            if (Build.VERSION.SDK_INT >= 30) {
                window.setDecorFitsSystemWindows(false);
                WindowInsetsController controller = window.getInsetsController();
                if (controller != null) {
                    controller.hide(WindowInsets.Type.systemBars());
                    controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                }
            }
        } catch (Throwable ignored) {
            // Gagal menyembunyikan bar tidak boleh membuat game berhenti.
        }
    }

    /** Beri padding aman (poni/status/navigasi) di atas padding dasar sebuah view. */
    public static void padForInsets(final View view, final int left, final int top, final int right, final int bottom) {
        view.setPadding(left, top, right, bottom);
        view.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @SuppressWarnings("deprecation")
            @Override public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                int il = insets.getSystemWindowInsetLeft();
                int it = insets.getSystemWindowInsetTop();
                int ir = insets.getSystemWindowInsetRight();
                int ib = insets.getSystemWindowInsetBottom();
                if (Build.VERSION.SDK_INT >= 28) {
                    DisplayCutout cutout = insets.getDisplayCutout();
                    if (cutout != null) {
                        il = Math.max(il, cutout.getSafeInsetLeft());
                        it = Math.max(it, cutout.getSafeInsetTop());
                        ir = Math.max(ir, cutout.getSafeInsetRight());
                        ib = Math.max(ib, cutout.getSafeInsetBottom());
                    }
                }
                v.setPadding(left + il, top + it, right + ir, bottom + ib);
                return insets;
            }
        });
        view.requestApplyInsets();
    }
}
