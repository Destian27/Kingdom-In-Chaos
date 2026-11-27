# Google Auth — konfigurasi Web + Android Client v17.14.3

## Credential yang dipakai

- **Web OAuth Client ID**: ID yang diberikan untuk integrasi server / audience ID token. Nilainya sudah menjadi fallback publik di `supabase/functions/google-player/index.ts` melalui `GOOGLE_WEB_OAUTH_CLIENT_ID`.
- **Android OAuth Client ID**: buat credential bertipe Android tersendiri untuk package `com.destian.kingdominchaosdtp` dan SHA-1 signing certificate yang dipakai saat build. Set sebagai `GOOGLE_ANDROID_OAUTH_CLIENT_ID` pada Edge Function. Jangan isi dengan Web Client ID.
- **Client Secret**: jangan pernah ditanam ke TS yang dibagikan, HTML, APK, atau GitHub repo. Flow Android saat ini meminta access token melalui Google Play Services lalu memvalidasinya ke Google UserInfo; flow itu tidak membutuhkan Client Secret. Edge Function juga menerima ID token yang audience-nya harus cocok dengan Web Client ID, tanpa Client Secret.

Secret yang sebelumnya dikirim melalui chat sebaiknya dirotasi di Google Cloud Console. Jangan gunakan nilai lama lagi. Bila kelak aplikasi beralih ke Authorization Code exchange di server, simpan secret BARU hanya sebagai secret environment Edge Function, misalnya `GOOGLE_OAUTH_CLIENT_SECRET`; jangan masukkan nilainya ke file source.

## Cara verifikasi token

1. **Access token Android (flow APK saat ini)** divalidasi oleh `https://openidconnect.googleapis.com/v1/userinfo`. Jika `GOOGLE_ANDROID_OAUTH_CLIENT_ID` disetel, server juga memeriksa `issued_to`/`aud` token terhadap Android Client ID.
2. **ID token Google** divalidasi lewat endpoint Google `tokeninfo`. Server memastikan `aud` sama persis dengan `GOOGLE_WEB_OAUTH_CLIENT_ID`, issuer berasal dari Google, token belum kedaluwarsa, dan email sudah terverifikasi.
3. Email yang belum verified ditolak. Data token tidak dicatat ke activity log.

## Environment Edge Function

Atur pada `google-player`:

```sh
GOOGLE_WEB_OAUTH_CLIENT_ID=709171564273-tgg9tklkjsp02tovhganpdr3cqspnc2r.apps.googleusercontent.com
GOOGLE_ANDROID_OAUTH_CLIENT_ID=<Android OAuth Client ID untuk package + SHA-1>
```

`GOOGLE_WEB_OAUTH_CLIENT_ID` sudah ada sebagai fallback di source, sehingga environment override bersifat opsional. `GOOGLE_ANDROID_OAUTH_CLIENT_ID` sangat disarankan agar access token APK ikut dipasangkan dengan credential Android yang benar.

Setelah mengubah environment, deploy ulang Edge Function `google-player`.

## Penting untuk alur APK saat ini

Java `GooglePlayerBackend.java` pada rilis v17.14.2 masih mengirim **access token** dari `GoogleAuthUtil`, bukan ID token. Jadi konfigurasi Web Client ID yang ditambahkan di TS menyiapkan verifikasi ID token, tetapi tidak mengganti mekanisme login Java. Untuk menggunakan ID token Web Client secara aktif, sisi Android harus meminta ID token dengan Web Client ID sebagai server client ID dan mengirimkannya sebagai Bearer token. Jangan mengirim Client Secret dari APK.
