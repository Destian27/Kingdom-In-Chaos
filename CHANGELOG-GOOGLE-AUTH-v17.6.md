# CHANGELOG — Google Auth v17.6

Tanggal: 26 November 2026

## Perubahan
- Menambahkan Supabase Google OAuth Authorization Code + PKCE.
- Redirect Android: `kingdominchaosdtp://auth`.
- Menambahkan `GameAuthActivity` dengan judul `Login ke Kingdom In Chaos DTP`.
- Login button memakai ikon game dari `@drawable/icon` sebagai pengganti logo Google.
- Menambahkan tombol `LOGIN` / `AKUN` pada overlay utama agar pemain bisa masuk ke halaman autentikasi/akun.
- Online Hub mengarahkan pemain ke login Google ketika fungsi autentikasi dibutuhkan dan sesi belum tersedia.
- Login email/password lama tetap tersedia sebagai jalur alternatif.
- Access token dan refresh token tetap ditulis ke penyimpanan terenkripsi Android Keystore melalui SupabaseGameBackend.

## Setup dashboard yang diperlukan
1. Aktifkan Google di Supabase Authentication → Providers → Google.
2. Masukkan Web OAuth Client ID dan Client Secret.
3. Di Google Cloud, tambahkan `https://gunzwimrxspbmiducphg.supabase.co/auth/v1/callback` sebagai Authorized redirect URI pada Web OAuth Client.
4. Tambahkan `kingdominchaosdtp://auth` ke Supabase Authentication → URL Configuration → Redirect URLs.

## Batasan yang diketahui
- Login Google memakai browser sistem dan kembali melalui custom scheme.
- Tombol akun merupakan pintu masuk login dari overlay Java.
- Source C++ untuk tombol avatar dan menu online asli tidak ada di arsip; tidak ada perubahan yang mengklaim memetakan semua tap native tersebut.
- APK belum dikompilasi dan belum diuji di perangkat dalam sesi pengeditan ini.
