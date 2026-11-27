# CHANGELOG — v17.14.6 Wallet Crash Fix

Tanggal: 27 November 2026 | Basis: v17.14.5
Masalah: game keluar sendiri setiap kali layar maintenance lolos — saat menekan **Cek Lagi**, dan saat membuka
aplikasi lewat data seluler. (Di Wi-Fi yang memblokir server, layar "AKSES DITAHAN" tampil terus sehingga game
tidak pernah dibuka dan crash tidak terlihat.)

## Bukti (laporan 27 Nov 2026 17:00, Xiaomi M2003J15SC, Android 10, v17.14.5)
```
Fatal signal 11 (SIGSEGV), fault addr 0x18, tid == pid (thread utama / UI)
#00 libgame.so  DHValue::getValue() const+2          (0x3E1986)
lr  = 0x3E1BA1  -> DHInt::getIntValue(int) const+16  (pemanggil langsung)
r9  = LevelManager::getCoin()      (0x29AA6D)
r10 = LevelManager::getCrystal()   (0x29AAA1)
r11 = LevelManager::getGoblinCoin()(0x29AAED)
r6  = BalanceLifeStatus(int*,int*) (0x3053A1)
```
Register pemanggil menyimpan persis keempat fungsi yang dipanggil `getWalletNative` (game_runtime_bridge.cpp),
dan crash terjadi di thread utama ~0,2 detik setelah `GameActivity onCreate` selesai.

## Penyebab
- `DtpApp.onGameResumed` -> `GameOnlineOverlay.install` -> `installEconomyHooksLater` ->
  `NativeGameRuntimeBridge.installEconomyHooks()` memanggil `seedLifetimeDmFromCurrentWallet()` -> `getWalletNative()`
  langsung di **thread UI**, begitu GameActivity resume.
- Saat itu `LevelManager::getInstance()` sudah non-NULL (cek `GAME_STATE_NOT_READY` lolos), tetapi data DHInt di
  dalamnya belum dimuat. `getCoin()` membaca anggota dari pointer NULL (offset 0x18) -> `DHValue::getValue()` SIGSEGV.

## Koreksi atas v17.14.4
v17.14.4 menyimpulkan penyebabnya elemen harga kosong di `price.xml`. Perbaikan itu (sudah terpasang di v17.14.5)
tidak menghilangkan crash: backtrace `DHValue::getValue()+2` yang sama muncul lagi, tetapi dengan pemanggil
`DHInt::getIntValue` dari jalur saldo, bukan `PriceManager`. Patch `price.xml` dibiarkan (tidak berbahaya).

## Perbaikan
- `game_runtime_bridge.cpp`: pembacaan saldo (`getWalletNative`, `applyWalletTargetsNative`, `applyEconomyNative`)
  dibungkus pelindung `SIGSEGV` (`sigsetjmp/siglongjmp`). Bila data game belum siap, fungsi mengembalikan
  `GAME_STATE_NOT_READY|...` dan game tetap hidup. Fault di luar blok terlindung diteruskan ke handler sebelumnya,
  jadi crash lain tidak disembunyikan. Mekanisme diuji di host dengan null-deref nyata (1000x berulang).
- `NativeGameRuntimeBridge.java`: `installEconomyHooks()` tidak lagi membaca saldo. Meter DM di-seed secara malas
  saat `getWallet()` pertama berhasil (game sudah siap), atau dari hook `IncreaseCrystal` bila belum ter-seed.
- `MaintenanceActivity.java`: layar "AKSES DITAHAN" kini menampilkan baris `Detail:` (mis. `UnknownHostException`,
  `HTTP 401`, `SocketTimeoutException`) supaya penyebab kegagalan cek server di Wi-Fi bisa diketahui.
- Versi: `versionName 17.14.6`, `versionCode 15`, output `KingdomInChaosDTP-v17.14.6-wallet-crashfix.apk`.
- Tes baru `tests/test_v17_14_6_wallet_crashfix.py`; tes versi lama diselaraskan.

## Batasan
- APK belum dibuild dan belum diuji di perangkat. Java tidak dikompilasi di sini (tidak ada javac/android.jar);
  C++ lolos `-fsyntax-only` dengan stub `jni.h`, dan pelindung diuji di host x86, bukan di ARMv7.
- Pelindung menangkap crash saat membaca saldo; ia tidak memuat data game lebih cepat. Jika game tetap keluar,
  kirim laporan crash baru (frame #00/lr dan register r9-r11 menunjukkan jalurnya).
