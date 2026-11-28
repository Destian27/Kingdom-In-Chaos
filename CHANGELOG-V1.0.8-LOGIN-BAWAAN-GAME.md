# CHANGELOG — v1.0.8 Masuk/Daftar bawaan game + Ganti Akun / Keluar

## Yang berubah (APK, versionCode 108)
- Pemain yang belum masuk memakai dialog **Masuk / Daftar BAWAAN game** (perkamen: Nama Pengguna, Kata Sandi 4–16,
  Verifikasi Kata Sandi, lalu popup nama panggilan/avatar/wilayah). Layar Java `GameAuthActivity` dan area sentuh
  penimpa (`Hotspots`) dihapus.
- Cara kerja: `libgame.so` (armeabi & armeabi-v7a) ditambal oleh `tools/patch_v1_0_8_local_auth.py` — hanya awalan tiga
  string URL (`login_v16.php`, `signup_v16.php`, `modify.php`) diganti `http://127.0.0.1:7391/` (panjang sama).
  `LocalAuthServer` di dalam aplikasi menjawab dengan JSON yang sama seperti server asli
  (`status/region/image/nickname`) dan meneruskan nama pengguna + kata sandi ke Edge Function lewat HTTPS.
  Semua toast, popup lanjutan, dan penyimpanan akun tetap dijalankan kode game asli.
- Setelah masuk muncul tombol **Akun** (kiri atas, di bawah ikon "!"): **Ganti Akun** dan **Keluar**.
  Keduanya menghapus token sesi DTP + enam kunci akun milik game (`Cocos2dxPrefsFile`), lalu game dimulai ulang.
  Setelah Ganti Akun muncul petunjuk untuk mengetuk kotak avatar.
- `build_dtp.py` menjalankan patch otomatis (`patch_local_auth`); output `KingdomInChaosDTP-v1.0.8.apk`.

## Server
- Tidak ada perubahan SQL / Edge Function (tetap v1.0.7).

## Batasan (jujur)
- Belum dibuild/diuji di perangkat. Format permintaan/jawaban diambil dari disassembly (hasil_bongkar2) dan string libgame.so;
  kode Java lolos pemeriksaan sintaks `javac`, dan tes struktur lolos.
- Ubah kata sandi dari popup game belum didukung server (ditolak dengan pesan jelas).
- Nama pengguna/kata sandi dikirim game apa adanya di URL loopback; karakter `&`, `#` di kata sandi tidak didukung.
- Jika port 7391 dipakai aplikasi lain, Masuk/Daftar menampilkan galat jaringan.
