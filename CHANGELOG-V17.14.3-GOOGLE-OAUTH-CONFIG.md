# CHANGELOG v17.14.3 — Google OAuth Client Configuration

- Menambahkan Web OAuth Client ID yang diberikan sebagai fallback publik `GOOGLE_WEB_OAUTH_CLIENT_ID` pada Edge Function `google-player`.
- Menambahkan verifikasi ID token Google: audience harus cocok persis dengan Web Client ID; issuer Google, masa berlaku, `sub`, email, dan `email_verified` diperiksa.
- Memisahkan `GOOGLE_ANDROID_OAUTH_CLIENT_ID` agar access token Android tidak salah dibandingkan dengan Web Client ID.
- Mempertahankan jalur access token Google Play Services pada APK v17.14.2.
- Client Secret tidak disimpan dalam source atau APK. Flow native saat ini tidak memerlukannya; secret yang terlanjur dibagikan harus dirotasi sebelum digunakan lagi.

## Batas kompatibilitas

Perubahan ini menambahkan konfigurasi/verifikasi di Edge Function. `GooglePlayerBackend.java` saat ini masih meminta access token dengan GoogleAuthUtil; ia belum diubah untuk meminta ID token dengan Web Client ID. Oleh sebab itu, pengujian APK/sign-in langsung masih diperlukan dan ID-token flow belum otomatis aktif hanya dengan mengubah TS.
