# CHANGELOG — v17.9 Automatic Full Crash Report

Tanggal: 27 November 2026
Basis: v17.8 Hero Stack Fix

## Masalah yang dituju

Laporan crash sebelumnya dibuat secara asynchronous, tetapi UI game tidak diberi tahu ketika file laporan selesai ditulis. Akibatnya tombol laporan dapat tidak muncul pada sesi yang sama, dan pemain tidak melihat laporan otomatis setelah membuka aplikasi kembali. Penanda sesi juga dihapus pada setiap `onActivityPaused`, padahal pause biasa bukan bukti bahwa game ditutup secara normal.

## Perbaikan v17.9

- `CrashReporter.onAppStart` memindahkan penanda sesi sebelumnya ke file pending. File pending tidak dihapus sampai laporan berhasil disimpan.
- Penanda tidak lagi dihapus saat `GameActivity.onPause`; ini mempertahankan jejak jika proses dihentikan saat aplikasi berada di background. Penanda hanya dibersihkan pada exit normal eksplisit (`Activity` finishing) atau maintenance kick yang disengaja.
- Menambahkan `Thread.UncaughtExceptionHandler` yang menyimpan waktu, thread, exception, dan stack trace Java secara lokal sebelum meneruskan ke handler Android yang sudah ada. Handler asli tidak diganti perilakunya dan crash tetap diteruskan.
- Laporan disusun di thread latar, ditulis melalui file sementara, lalu dipindahkan ke file laporan. Listener memberi tahu UI setelah penyimpanan selesai.
- Ketika aplikasi dibuka kembali, laporan otomatis ditampilkan di `MaintenanceActivity`/launcher. Jika laporan selesai dibuat setelah layar aktif, callback memperbarui UI dan langsung menampilkan dialog.
- Ikon kecil `!` tetap tersedia di overlay game untuk membuka kembali laporan. Dialog menyediakan `Salin Semua`, `Hapus Laporan`, dan `Tutup`. Laporan tidak dihapus hanya karena dibuka atau disalin.
- Isi laporan diperluas: identitas build perangkat dan APK, ABI, jejak sesi, Java stack trace jika tersedia, hingga 8 riwayat `ApplicationExitInfo` Android 11+, trace/tombstone yang dapat dibaca, dan logcat relevan. Token, password, dan kredensial umum disamarkan.
- Laporan disimpan di direktori privat aplikasi dan tidak dikirim ke server.
- Metadata paket Android dinaikkan ke `versionName=17.9`, `versionCode=7`; nama output build menjadi `KingdomInChaosDTP-v17.9.apk`.

## Batasan

- Android dapat membatasi aplikasi biasa membaca logcat sistem. Akses trace/tombstone dari `ApplicationExitInfo` juga bergantung pada perangkat dan versi Android. Jadi laporan mengumpulkan semua informasi yang diizinkan OS, tetapi tidak dapat menjamin setiap jenis crash memiliki seluruh log native.
- Source telah dimodifikasi, tetapi APK belum dikompilasi maupun diuji di perangkat dalam sesi ini karena Android SDK/NDK dan `apktool.jar` tidak tersedia di lingkungan kerja.
- Crash native yang menghentikan proses sebelum Java berjalan ditangkap melalui penanda sesi dan `ApplicationExitInfo` (jika Android menyediakan informasinya), bukan melalui Java uncaught-exception handler.

## Berkas utama

- `dtp/src/com/destian/dtp/CrashReporter.java`
- `dtp/src/com/destian/dtp/DtpApp.java`
- `dtp/src/com/destian/dtp/GameOnlineOverlay.java`
- `kingdom-in-chaos-decompiled/apktool.yml`
- `build_dtp.py`
