# Paket Bahasa Indonesia — Kingdom in Chaos DTP

## Isi terjemahan

Paket ini melokalkan data teks yang tersedia dalam konfigurasi game, termasuk:

- antarmuka utama, tombol, pesan, tutorial, dan petunjuk;
- nama serta deskripsi hero dan kemampuan/skill;
- nama perlengkapan dan deskripsi efek;
- pencapaian, misi, nama lokasi, dialog cerita, teks toko, dan nama kartu.

Sebanyak **2.254 entri teks** di dalam konfigurasi diproses. Pemeriksaan otomatis membandingkan token placeholder pada **2.279 node XML** dan tidak menemukan perbedaan (`placeholder_mismatches: 0`). Ini membantu mencegah format nilai seperti `%d`, `%s`, `%P`, dan format khusus game berubah akibat penerjemahan.

## Pemasangan pada source decompile

1. Buat cadangan source terlebih dahulu.
2. Ekstrak paket Bahasa Indonesia ke folder root source yang berisi `AndroidManifest.xml`, dengan mempertahankan struktur folder di dalam ZIP.
3. File penting yang digunakan game:
   - `assets/public/config/string/de.xml` — slot runtime bahasa yang dipakai native game saat ini;
   - `assets/public/config/string/id.xml` — file locale Indonesia dengan nama kanonis untuk pengembangan native selanjutnya;
   - `assets/public/config/global.xml` — label pilihan bahasa;
   - `res/values/strings.xml` — teks label di dialog bahasa Android.
4. Build source dari lingkungan Android yang lengkap, atau push source ke GitHub dan jalankan workflow `Build Kingdom In Chaos DTP APK` yang tersedia.
5. Pasang APK hasil build dan periksa menu bahasa, teks yang panjang, dialog, tutorial, toko, dan level game di perangkat.

Untuk build lokal dibutuhkan JDK 17+, Android SDK beserta build-tools/platform yang sesuai, serta `tools/apktool.jar`. Jalankan `python3 build_dtp.py` dari root source. Berkas APK belum dibangun oleh sesi penyuntingan ini karena Android SDK dan `apktool.jar` tidak tersedia di lingkungan kerja ini.

## Batasan yang perlu diketahui

- Native game yang tersedia hanya memiliki **lima slot bahasa**. Tidak ada source C++ native yang memungkinkan menambahkan slot keenam dengan aman pada pekerjaan ini. Karena itu, label **Deutsch** dan data runtime `de.xml` dialihkan untuk Bahasa Indonesia. Bahasa Jerman tidak lagi tersedia pada build ini.
- Berkas `id.xml` dibuat dengan nama standar untuk kebutuhan pengembangan atau setelah enum native ditambah di masa mendatang. Build saat ini menggunakan `de.xml` sebagai alias runtime.
- Teks yang sudah menyatu ke gambar/tekstur, teks yang di-hardcode di `libgame.so`, teks dari sistem Android, dan respons server yang tidak berada di XML ini tidak otomatis diterjemahkan oleh perubahan ini.
- Nama tokoh, tempat, artefak, serta istilah fantasi tertentu dipertahankan bila merupakan nama khusus. Terjemahan perlu ditinjau secara visual dan linguistik saat game dijalankan.
- XML valid dan pemeriksaan source lulus, tetapi hal itu bukan bukti APK telah dibangun atau semua layar telah diuji pada perangkat nyata.

## Pemeriksaan yang dijalankan

- XML locale `id.xml` dan alias runtime `de.xml` berhasil didekompresi dan diparsing ulang.
- Jumlah entri teks yang diproses: **2.254**.
- Placeholder tidak cocok: **0**.
- Tes source: **38 lulus, 2 dilewati**.
- APK final / pemasangan perangkat: **belum diuji**.
