# v17.14.14 — Layar penuh + pemilih akun Google profesional

- Game (GameActivity, via smali): memanggil ImmersiveHelper.apply saat onCreate dan setiap jendela fokus.
  Status bar dan tombol navigasi disembunyikan (immersive sticky), area poni/kamera terisi
  (layoutInDisplayCutoutMode = SHORT_EDGES). Tidak ada lagi pita hitam di sisi kiri dan
  menu kanan (Surat, Bakat, Perlengkapan, Tim) tidak terpotong tombol navigasi.
- GameAuthActivity (Login Google): layar penuh, konten di tengah, padding aman untuk poni.
- Baru: GoogleAccountPickerActivity — halaman "Pilih Akun Google" layar penuh dengan ikon game,
  kartu akun berinisial, penanda "Terakhir dipakai", tombol "Gunakan akun lain" dan "Batal".
  Memerlukan izin GET_ACCOUNTS (diminta saat pertama). Bila izin ditolak atau tidak ada akun,
  memakai dialog pilih akun bawaan Android sebagai cadangan.
- AndroidManifest: tambah GoogleAccountPickerActivity.
