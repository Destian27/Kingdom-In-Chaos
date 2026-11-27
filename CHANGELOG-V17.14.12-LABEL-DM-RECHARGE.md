# CHANGELOG — v17.14.12 Label DM + daging normal + Total Recharge DM

Tanggal: 28 November 2026 · Basis: v17.14.10

## Sudah dikerjakan
- Label harga di layar Penawaran: `sign` di `price.xml` dari "Rp" menjadi "DM", dan 23 elemen `<dollar>` diisi nominal barter
  (Newbie Value 299, Rich 999, Weekly 599, PvP 99, Equipment 499, Hero bundle 560, Gear bundle 420, Seasonal 499/1499,
  unlockHero 140/350/1400/490/490/700, coinPrice 200/700/2400).
- Format harga native `"%s%.2f"` -> `"%s%.0f"` di `libgame.so` (armeabi & armeabi-v7a, panjang sama), jadi tampil `DM299`, bukan `Rp299.00`.
- Skrip baru `tools/patch_dm_labels.py` (idempoten), dipanggil dari `build_dtp.py`.
- Tes `test_barter_economy_v17_12` disesuaikan (sign "DM", nominal terisi). Komentar di `GameProfileSetupActivity.java`
  memakai kata "password" sehingga tes v17.14.10 gagal; kata diganti "kata sandi" (hanya komentar).

- **Daging**: Fix 6 "Unlimited Stamina" dicabut. `BalanceLifeStatus` (@0x3053A0, 18 byte) dan `DecreaseLife` (@0x3055FC, 4 byte)
  dikembalikan ke byte asli dari `kingdom-in-chaos-1-0-5.apk` di kedua ABI. Regen 1 per 5 menit (`lifeRecoveryInterval`=300), kapasitas 24
  (patch LifeMax tetap). Konsekuensi: stage kembali memakai daging. Patch lama dulu dibuat agar ikon daging tidak meluap; belum diuji apakah itu muncul lagi.

- **Total Recharge**: ambang float di `PriceManager::addFirstAddUpGift` (@0x2BE208..0x2BE214) diubah 20/50/150/500 -> 40/100/300/1000
  (skrip `tools/patch_total_recharge.py`, kedua ABI, hanya data). Puncak 1.000 = keempat hadiah bisa diklaim memakai logika klaim bawaan.
  Progres bertambah lewat `handlePaidOK()` = jumlah harga (DM) pembelian barter yang berhasil, BUKAN kristal yang diperoleh dari bermain.
  Nilai item berbayar Koin (VIP, Luck Spree, paket kristal) di `price.xml` dibuat setara DM (600/70/200/700/2400) supaya satu pembelian tidak langsung menembus 1.000.

## BELUM dikerjakan / diketahui
2. **Progres dari kristal yang didapat**: belum. Progres sekarang dari DM yang dibelanjakan. Mengikuti kristal yang masuk perlu memanggil `increaseAddUpDiscountCash` dari hook `IncreaseCrystal` (argumen id diskon belum dipetakan penuh).
3. **Tampilan terpotong setelah kembali dari paket Newbie**: belum diselidiki (butuh uji di perangkat).
4. **Label item berbayar Koin**: VIP, Luck Spree dan paket kristal tampil "DM600/70/200/700/2400" (setara DM) padahal dipotong dalam KOIN (30.000/3.500/10.000/35.000/120.000).
5. Urutan `unlockHero*` -> `heroCosts[]` adalah asumsi, belum diuji di game.
6. APK belum dikompilasi/diuji (tidak ada SDK/NDK di lingkungan ini).
