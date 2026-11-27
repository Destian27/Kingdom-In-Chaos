package com.destian.dtp;

import android.accounts.Account;
import android.accounts.AccountManager;
import android.app.Activity;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Locale;

/**
 * v17.14.14 — pemilih akun Google layar penuh (pengganti dialog "Pilih akun").
 * Hasil: RESULT_OK + KEY_ACCOUNT_NAME, atau RESULT_FIRST_USER untuk "Gunakan akun lain".
 */
public final class GoogleAccountPickerActivity extends Activity {
    private static final int BG_TOP = 0xFF101A31;
    private static final int BG_BOTTOM = 0xFF263B62;
    private static final int GOLD = 0xFFFFD36A;
    private static final int MUTED = 0xFFD5DDF0;
    private static final int[] AVATAR_COLORS = {
            0xFF1E88E5, 0xFF8E24AA, 0xFF00897B, 0xFFF4511E, 0xFF3949AB, 0xFF6D4C41, 0xFFD81B60, 0xFF43A047};

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        ImmersiveHelper.apply(this);
        Account[] accounts;
        try { accounts = AccountManager.get(this).getAccountsByType("com.google"); }
        catch (Exception e) { accounts = new Account[0]; }
        if (accounts.length == 0) {
            setResult(RESULT_FIRST_USER);
            finish();
            return;
        }
        buildUi(accounts);
    }

    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) ImmersiveHelper.apply(this);
    }

    private void buildUi(Account[] accounts) {
        FrameLayout root = new FrameLayout(this);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{BG_TOP, BG_BOTTOM}));

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setGravity(Gravity.CENTER_HORIZONTAL);
        root.addView(page, new FrameLayout.LayoutParams(-1, -1));
        ImmersiveHelper.padForInsets(page, dp(22), dp(28), dp(22), dp(20));

        ImageView logo = new ImageView(this);
        int iconId = getResources().getIdentifier("icon", "drawable", getPackageName());
        if (iconId != 0) logo.setImageResource(iconId);
        logo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        logo.setClipToOutline(true);
        logo.setOutlineProvider(new ViewOutlineProvider() {
            @Override public void getOutline(View view, Outline outline) {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), dp(24));
            }
        });
        logo.setElevation(dp(6));
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(dp(96), dp(96));
        logoParams.bottomMargin = dp(16);
        page.addView(logo, logoParams);

        TextView title = new TextView(this);
        title.setText("Pilih Akun Google");
        title.setTextColor(GOLD); title.setTextSize(24); title.setGravity(Gravity.CENTER);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        page.addView(title, new LinearLayout.LayoutParams(-1, -2));

        TextView subtitle = new TextView(this);
        subtitle.setText("Pilih akun yang akan dipakai untuk Kingdom In Chaos DTP");
        subtitle.setTextColor(MUTED); subtitle.setTextSize(14); subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams subParams = new LinearLayout.LayoutParams(-1, -2);
        subParams.topMargin = dp(8); subParams.bottomMargin = dp(20);
        page.addView(subtitle, subParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(false);
        scroll.setVerticalScrollBarEnabled(false);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, new FrameLayout.LayoutParams(-1, -2));
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));

        String saved = new GooglePlayerBackend(getApplicationContext()).getSavedAccountName();
        for (Account account : accounts) addAccountRow(list, account.name, account.name.equalsIgnoreCase(saved));

        Button other = new Button(this);
        other.setText("Gunakan akun lain"); other.setAllCaps(false);
        other.setTextColor(GOLD); other.setTextSize(15); other.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        GradientDrawable otherBg = new GradientDrawable();
        otherBg.setColor(Color.TRANSPARENT); otherBg.setCornerRadius(dp(14)); otherBg.setStroke(dp(1), GOLD);
        other.setBackground(otherBg);
        other.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { setResult(RESULT_FIRST_USER); finish(); }
        });
        LinearLayout.LayoutParams otherParams = new LinearLayout.LayoutParams(-1, dp(52));
        otherParams.topMargin = dp(14);
        page.addView(other, otherParams);

        Button cancel = new Button(this);
        cancel.setText("Batal"); cancel.setAllCaps(false);
        cancel.setTextColor(MUTED); cancel.setTextSize(14);
        cancel.setBackgroundColor(Color.TRANSPARENT);
        cancel.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { setResult(RESULT_CANCELED); finish(); }
        });
        LinearLayout.LayoutParams cancelParams = new LinearLayout.LayoutParams(-1, dp(46));
        cancelParams.topMargin = dp(4);
        page.addView(cancel, cancelParams);

        setContentView(root);
    }

    private void addAccountRow(LinearLayout list, final String email, boolean lastUsed) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        GradientDrawable card = new GradientDrawable();
        card.setColor(0x24FFFFFF); card.setCornerRadius(dp(16));
        card.setStroke(dp(1), lastUsed ? GOLD : 0x33FFFFFF);
        row.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33FFD36A), card, null));
        row.setClickable(true);
        row.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent result = new Intent();
                result.putExtra(AccountManager.KEY_ACCOUNT_NAME, email);
                result.putExtra(AccountManager.KEY_ACCOUNT_TYPE, "com.google");
                setResult(RESULT_OK, result);
                finish();
            }
        });

        TextView avatar = new TextView(this);
        String letter = email.isEmpty() ? "?" : email.substring(0, 1).toUpperCase(Locale.ROOT);
        avatar.setText(letter); avatar.setTextColor(Color.WHITE); avatar.setTextSize(18);
        avatar.setGravity(Gravity.CENTER); avatar.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        GradientDrawable circle = new GradientDrawable();
        circle.setShape(GradientDrawable.OVAL);
        circle.setColor(AVATAR_COLORS[(email.hashCode() & 0x7fffffff) % AVATAR_COLORS.length]);
        avatar.setBackground(circle);
        row.addView(avatar, new LinearLayout.LayoutParams(dp(44), dp(44)));

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(0, -2, 1f);
        textParams.leftMargin = dp(14); textParams.rightMargin = dp(8);
        row.addView(text, textParams);

        TextView name = new TextView(this);
        name.setText(email); name.setTextColor(Color.WHITE); name.setTextSize(15);
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        name.setSingleLine(true); name.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);
        text.addView(name, new LinearLayout.LayoutParams(-1, -2));

        TextView sub = new TextView(this);
        sub.setText(lastUsed ? "Terakhir dipakai" : "Akun Google");
        sub.setTextColor(lastUsed ? GOLD : MUTED); sub.setTextSize(12);
        text.addView(sub, new LinearLayout.LayoutParams(-1, -2));

        TextView arrow = new TextView(this);
        arrow.setText("›"); arrow.setTextColor(GOLD); arrow.setTextSize(26);
        row.addView(arrow, new LinearLayout.LayoutParams(-2, -2));

        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(-1, -2);
        rowParams.bottomMargin = dp(10);
        list.addView(row, rowParams);
    }

    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
}
