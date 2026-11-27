# v17.14.13 — Perbaikan Login Google

Masalah: "Login Google gagal: Google Auth tidak kompatibel dengan versi Google Play Services ini."

Penyebab: APK membawa salinan lama GoogleAuthUtil (hasil dekompilasi game) yang hanya punya
getToken(Context, String, String) dan getToken(Context, String, String, Bundle).
GooglePlayerBackend memanggil getToken(Context, Account, String) lewat refleksi,
sehingga NoSuchMethodException dan pesan "tidak kompatibel" muncul.

Perbaikan (GooglePlayerBackend.java):
- Coba getToken(Context, String, String) lebih dulu, lalu getToken(Context, Account, String).
- LinkageError ikut ditangkap sebagai ketidakcocokan versi.
- Cadangan: bila GoogleAuthUtil gagal, ambil token lewat AccountManager.getAuthToken
  (API bawaan Android, tanpa pustaka tertanam). Intent persetujuan Google tetap
  diteruskan lewat RecoverableGoogleAuthException.
- Sisi server (google-player), SQL, dan admin tidak berubah.
