# CHANGELOG — v17.14.5 UI Polish (teks Indonesia + bendera bahasa)

Tanggal: 27 November 2026 | Basis: v17.14.4

## Teks meluap / tidak rapi
- Penyebab: terjemahan ~25% lebih panjang dan satu baris, sedangkan versi Inggris memakai pemisah
  baris manual (&#x0A;) dan label game tidak membungkus otomatis. Contoh skill Vampir: Inggris 2 baris,
  Indonesia 1 baris 97 huruf -> melewati tepi papan.
- Perbaikan (`tools/patch_ui_polish.py`): lebar acuan = baris terpanjang versi Inggris (24..72 huruf);
  baris Indonesia yang lebih panjang dibungkus per kata; keterangan "(...)" dipisah ke baris sendiri
  bila versi Inggris juga begitu. Berlaku untuk seluruh string (skill, hero, tutorial, dialog, UI).
- Label sempit: "Nilai Pertumbuhan" -> "Pertumbuhan" (menimpa label Skill), "Ski/ll" -> "Skill",
  "Bang/kit" -> "Bang-/kit". "Paket Dollar" di runtime -> "Paket Barter".
- Diterapkan ke `de.xml` (slot runtime), `id.xml`, dan `translation-source/id.xml`.

## Bendera pilihan bahasa
- Slot Bahasa Indonesia memakai frame `UI/de.png` (bendera Jerman): kini diarahkan ke bendera Indonesia
  (merah-putih) lewat `nation.plist`.
- Slot English memakai gambar bintang tunggal mirip Liberia: `UI/us.png` digambar ulang (13 garis,
  kanton biru, bintang). `nation.png` dienkripsi XXTEA; enkripsi ulang diverifikasi identik byte-per-byte.

## Batasan
- APK belum dibuild/diuji di perangkat. Lebar kotak tiap layar tidak bisa diukur dari sini; aturannya
  memakai lebar versi Inggris sebagai patokan. Teks yang tertanam di gambar tidak ikut berubah.
- Flag "de" kini juga tampil Indonesia untuk pemain bernegara Jerman di papan peringkat.
- Bendera slot 中文(繁体) tetap bendera RRC (`cn`) seperti game asli; belum diubah.
