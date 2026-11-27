# v17.14.15 — Semua pembelian toko memakai Kristal (DM)

- VIP 30 hari: 30.000 Koin -> 600 DM (Kristal). Label di toko sudah "DM600".
- Luck Spree: 3.500 Koin -> 70 DM (Kristal). Label di toko sudah "DM70".
- Relik / Perlengkapan individual (paymentId 41-48): tetap 499 DM, semuanya dibayar Kristal.
- Paket Hero, Perlengkapan, Mingguan, Newbie, Tiket PvP, Musiman: tetap dibayar Kristal.
- Tab Koin dan Kristal tetap berupa penukaran dua arah (50 Koin = 1 DM) supaya Kristal tetap bisa didapat dari Koin.
- Berubah di: dtp/native/game_runtime_bridge.cpp (getOfferCost), GameOnlineOverlay.java (menu BARTER),
  assets/dtp_barter_prices.json, tools/patch_dm_labels.py (komentar), tests/test_barter_economy_v17_12.py.
- Tes proyek yang relevan lulus (28 tes). APK belum dibuild atau diuji di perangkat.
- Nama output APK dikembalikan ke KingdomInChaosDTP-v17.14.8-price-barter-crashfix.apk karena
  .github/workflows/build-apk.yml memakai nama itu (rename di v17.14.14 akan merusak unggahan artefak CI).
