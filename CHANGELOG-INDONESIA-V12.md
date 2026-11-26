# Changelog Bahasa Indonesia v12 — 26 November 2026

- Memproses 2.254 entri teks dari XML konfigurasi game ke Bahasa Indonesia.
- Melokalkan antarmuka, tutorial, tips, hero, skill, perlengkapan, pencapaian, misi, dialog cerita, lokasi, toko, dan kartu.
- Membuat `assets/public/config/string/id.xml` sebagai locale bernama Indonesia dan `de.xml` sebagai alias runtime untuk slot kelima yang saat ini digunakan native game.
- Mengubah label opsi bahasa yang sebelumnya Deutsch menjadi Bahasa Indonesia.
- Mengubah label `title14` pada konfigurasi global menjadi `Bahasa Indonesia`.
- Menjaga semua placeholder pada 2.279 node XML; pemeriksaan mendeteksi 0 ketidaksesuaian.
- Memperbarui skrip lokalisasi agar menerjemahkan frasa perlengkapan dan tidak menggunakan penerjemahan token yang merusak frasa.
- Menambahkan panduan paket bahasa.

## Batasan

Slot native keenam tidak ditambahkan karena source C++/enum native tidak tersedia; slot Deutsch digantikan. Teks yang menyatu pada aset visual atau terhardcode di `libgame.so` belum dilokalkan. APK belum dibangun dan diuji di perangkat pada sesi ini.
