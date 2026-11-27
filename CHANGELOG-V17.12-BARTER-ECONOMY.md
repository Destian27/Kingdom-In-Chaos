# CHANGELOG — v17.12 Barter Economy

Tanggal: 27 November 2026  
Basis: Kingdom In Chaos DTP v17.11

## Perubahan utama

- Jalur Google Play / pembayaran uang asli pada `PriceManager::pay(int)` dinonaktifkan. Jika hook barter native tidak dapat dipasang, jalur pembelian lama tetap gagal-aman dan tidak membuka pembayaran uang. Paket mata uang lama (ID 2–25) dialihkan langsung ke konversi Koin/DM, bukan ke callback hadiah pembelian tunai.
- Pada ARMv7, hook native mengganti jalur bayar dengan pemotongan saldo **Koin atau DM**. Hadiah tetap diproses oleh `PriceManager::onPaidOK()` asli setelah pengurangan saldo berhasil.
- Pemanggilan native untuk mencatat transaksi uang dan statistik pembayaran dinonaktifkan. Toast sukses uang diganti ke toast hadiah umum.
- Menu **BARTER** di dalam game membaca saldo Koin/DM dari `LevelManager`, menampilkan daftar tukar mata uang dan paket, meminta konfirmasi, lalu memanggil transaksi native.
- Total DM terkumpul dihitung dari penambahan Kristal/DM yang benar-benar masuk melalui `IncreaseCrystal`. Saldo DM saat pertama kali hook aktif dipakai sebagai nilai awal lokal. Pengeluaran DM tidak menurunkan total akumulasi.
- Mata uang bisa ditukar dua arah dengan rasio 50 Koin untuk 1 DM, mengikuti paket mata uang bawaan yang sudah ada di konfigurasi game.
- Seluruh nilai harga dolar di `price.xml` dikosongkan. Tab paket dolar pada bahasa Indonesia dan Inggris diganti menjadi paket barter.

## Harga barter yang dipasang

| Item | Biaya |
|---|---:|
| VIP 30 hari | 30.000 Koin |
| Luck Spree | 3.500 Koin |
| Newbie Value Pack | 299 DM |
| Newbie Rich Pack | 999 DM |
| Perlengkapan individual (8 penawaran) | 499 DM per item |
| Paket Hero | 560 DM |
| Paket Perlengkapan | 420 DM |
| Paket Mingguan | 599 DM |
| Tiket PvP | 99 DM |
| Paket Musiman A | 499 DM |
| Paket Musiman B | 1.499 DM |

Untuk nilai tukar:

- 200 / 700 / 2.400 DM ditukar menjadi 10.000 / 35.000 / 120.000 Koin.
- 10.000 / 35.000 / 120.000 Koin ditukar menjadi 200 / 700 / 2.400 DM.

Harga selain VIP 30 hari adalah nilai barter awal untuk menutup pembayaran uang lama. Nilai yang tidak ditetapkan langsung oleh pengguna dipilih dari nilai paket/rasio yang ada di konfigurasi game dan perlu diuji di dalam game.

## Progres DM

Bar progres pada menu BARTER memakai total DM yang masuk, dengan ambang tampilan 2.000, 5.000, 15.000, dan 50.000 DM. Angka ini setara dengan ambang lama $20, $50, $150, dan $500 menggunakan konversi 100 DM per USD. Ini adalah progres lokal untuk akumulasi DM; klaim bonus “Total Recharge” lama yang bergantung pada server pembayaran tidak otomatis dipindahkan atau diklaim.

## Batas teknis dan pengujian

- `libgame.so` tersedia untuk ABI `armeabi` dan `armeabi-v7a`; pembayaran tunai dipadamkan statis di keduanya. Hook transaksi dan pencatatan DM dibuat untuk `armeabi-v7a`, ABI native utama pada perangkat Android modern.
- Library game asli bersifat biner dan source code asli untuk sistem toko/server tidak disertakan. Karena itu harga individual yang tidak ditentukan pengguna merupakan konfigurasi barter awal, bukan harga resmi game.
- Sumber Java, C++, Python, XML terkompresi, dan patch biner sudah diperbarui. Pemeriksaan sumber dan tes kompatibilitas dijalankan; APK belum dapat dikompilasi atau diuji pada perangkat dalam lingkungan ini karena Android SDK/NDK/apktool tidak tersedia.
- Versi APK: `versionName 17.12`, `versionCode 9`. Nama output build: `KingdomInChaosDTP-v17.12-barter.apk`.
