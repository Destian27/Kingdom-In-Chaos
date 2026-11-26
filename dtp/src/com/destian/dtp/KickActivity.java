package com.destian.dtp;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Process;

/** Berjalan di proses terpisah (:kick). Matikan proses game, lalu buka layar maintenance. */
public class KickActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int pid = getIntent().getIntExtra("pid", -1);
        Intent target = getIntent().getParcelableExtra("target");
        if (pid > 0) {
            Process.killProcess(pid);
        }
        if (target != null) {
            startActivity(target);
        }
        finish();
        Runtime.getRuntime().exit(0);
    }
}
