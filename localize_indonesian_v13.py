#!/usr/bin/env python3
"""Build a safer Indonesian locale for Kingdom in Chaos DTP's packed Cocos XML assets.

Important: this localizes the game's text config and reuses the native German locale slot
because the supplied native code exposes only five selectable locales. It does not alter
text baked into images or closed-source native code.
"""
from pathlib import Path
import json, re, zlib, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent / 'kingdom-in-chaos-decompiled'
STRING_DIR = ROOT / 'assets/public/config/string'
MAP_FILE = Path(__file__).resolve().parent / 'global_existing_indonesian.json'
GLOBAL = json.loads(MAP_FILE.read_text(encoding='utf-8'))

# Fix legacy map typos and fill all remaining main-interface strings by key.
GLOBAL.update({
    'official_version_backup_error_msg':'Gagal membuat salinan cadangan arsip!\n\nPeriksa kartu SD dan coba lagi nanti.',
    'talent_hp_title2':'HP Super', 'talent_attack_title2':'Serangan Super', 'talent_armor_title2':'Zirah Super',
    'talent_crit_desc':'Meningkatkan peluang kritis sebesar %d%%.',
    'talent_move_desc':'Meningkatkan kecepatan gerak sebesar %d%%.',
    'popupDescribe_saveGameRestartHint':'Unduhan arsip %d/%02d/%02d/%02d:%02d selesai. Perubahan akan berlaku setelah game dimulai ulang.',
    'tutorial_story_level1':'Ketuk di sini untuk memulai perjalananmu!',
    'tutorial_story_armory':'Atur perlengkapanmu di sini.',
    'tutorial_story_talent':'Pelajari bakat dan mantra lainnya di sini.',
    'tutorial_story_team':'Atur timmu di sini.',
    'tutorial_story_achieve':'Lihat pencapaianmu di sini.',
    'tutorial_story_rotary':'Ketuk untuk membuka Roda Keberuntungan.',
    'tutorial_gear_1':'Seret perlengkapan toko untuk memakainya.',
    'tutorial_gear_2':'Tingkatkan perlengkapan menggunakan Koin.',
    'tutorial_shop_1':'Kamu bisa membeli dan menjual perlengkapan di sini.',
    'tutorial_shop_2':'Tunggu untuk menyegarkan isi toko secara gratis.\nAtau gunakan sedikit Emas untuk menyegarkannya sekarang.',
    'tutorial_talent_1':'Ketuk untuk memilih bakat.',
    'tutorial_talent_2':'Ketuk di sini untuk mempelajarinya.\nMempelajari bakat membutuhkan Kristal.',
    'tutorial_talent_3':'Pilih mantra.', 'tutorial_talent_4':'Ketuk untuk mempelajarinya.',
    'tutorial_talent_spell':'Atur mantramu di sini.',
    'tutorial_spell_1':'Seret untuk memilih mantra.\n(Ketuk di mana saja untuk melanjutkan)',
    'tutorial_spell_2':'Slot mantra tambahan dapat dibuka.\n(Ketuk di mana saja untuk melanjutkan)',
    'tutorial_team_1':'Di sini kamu dapat merekrut hero baru. Coba sekarang!\nPilih hero.',
    'tutorial_team_2':'Ketuk untuk membeli. Gunakan 3 Kristal untuk mendapatkan hero!',
    'tutorial_team_3':'Ketuk untuk mengonfirmasi.',
    'tutorial_team_4':'Seret hero dan tempatkan ke dalam tim.',
    'tutorial_team_6':'Buka halaman kedua untuk melihat hero lainnya.',
    'tutorial_rotary':'Usap layar untuk memutar!\nSetiap putaran membutuhkan 5 Koin Goblin.',
    'tutorial_achieve_1':'Ketuk di sini untuk mendapatkan bonus!',
    'tutorial_achieve_2':'Bagikan pencapaianmu secara daring untuk mendapat lebih banyak hadiah!\n(Ketuk di mana saja untuk melanjutkan)',
    'tutorial_back':'Ketuk di sini untuk melanjutkan perjalananmu.\n(Ketuk di mana saja untuk melanjutkan)',
    'tutorial_back_force':'Ketuk untuk kembali ke Peta.',
    'tutorial_story_mission':'Lihat misi di sini.\nBanyak hadiah menantimu.',
    'defeat_free_coin':'gratis', 'world_boss_title_alchemist':'Lostwood sang Alkemis',
    'world_boss_desc_alchemist':'Lostwood adalah alkemis terbaik di kerajaan.\nSepanjang hidupnya, ia mengembangkan ramuan\nuntuk membuka seluruh potensi tubuh manusia.\nSayangnya, ia bereksperimen pada dirinya sendiri\ndan akhirnya dikuasai kegilaan.',
    'world_boss_title_introduction':'Pengantar',
    'world_boss_desc_introduction':'Ada dua acara Tantangan Bos setiap hari.\nAcara berakhir setelah 1 jam atau saat bos dikalahkan.\n\nLawan bos berulang kali; skor dari semua pertarunganmu\nakan dijumlahkan di papan peringkat.\n\nSetelah Tantangan Bos berakhir, buka tab “Peringkat”\nuntuk melihat posisimu dan mengklaim hadiah!',
    'heroBuffSlot_0':'Serangan +%d%%\nuntuk semua\nhero',
    'heroBuffSlot_1':'Kecepatan serang\n+%d%% untuk\nsemua hero',
    'heroBuffSlot_2':'Kecepatan merapal\nmeningkat %d%%\nuntuk semua hero',
    'heroBuffSlot_3':'Peluang kritis\n+%d%% untuk\nsemua hero',
    'heroBuffSlot_4':'HP +%d%%\nuntuk semua\nhero',
    'heroBuffSlot_5':'Kecepatan gerak\n+%d%% untuk\nsemua hero',
    'heroBuffSlot_6':'Zirah +%d%%\nuntuk semua\nhero',
    'heroBuffSlot_7':'Bonus skor\n+%d%%', 'heroBuffSlot_none':'Tidak tersedia',
    'tutorial_buffSlot':'Ketuk di sini untuk mendapat tiga bonus acak.\n(Kali ini kamu bisa menyegarkannya gratis)',
    'tutorial_world_boss_info':'Ketuk di sini untuk membaca pengantar acara.\n(Ketuk di mana saja untuk melanjutkan)',
    'convert_skillTitle':'Ringkasan mantra hero',
    'conquer_sync':'Kesempatan reset: %d',
    'conquer_desc_introduction':'1. Semakin jauh kamu melangkah, semakin banyak hadiah!\n\n2. Setiap hari tersedia satu kesempatan reset gratis.\n\n3. Semua hero yang telah dibuka dapat mengikuti Ekspedisi.\n\n4. Hero yang gugur tidak dapat bertarung lagi.',
    'tutorial_conquer1':'Mode Ekspedisi terbuka.\nKetuk untuk mulai.',
    'tutorial_conquer3':'Ketuk untuk melihat pengantar\nMode Ekspedisi.',
    'tutorial_world_boss':'Tantangan Bos terbuka.\nKetuk untuk melihat.',
    'ladder_introduction_desc':'1. Kesempatan gratis diperbarui setiap hari pukul %s.\n\n2. Pemain dengan Kehormatan di atas 7500 dan telah menyelesaikan %d pertarungan akan masuk ke Daftar Kehormatan!\n\n3. Setiap pertarungan memberimu Poin Peringkat.',
    'ladder_report_time_0':'%d menit lalu', 'ladder_report_time_1':'%d jam lalu', 'ladder_report_time_2':'%d hari lalu',
    'tutorial_card1':'Ketuk di sini untuk membuka Galeri Kartu.\nKamu bisa membeli kartu untuk digunakan di Arena.',
    'tutorial_card3':'Ketuk di sini untuk membeli Paket Kartu.',
    'tutorial_card4':'Ketuk untuk membeli Paket Kartu\n(PAKET BONUS GRATIS)',
    'tutorial_card5':'Ketuk di sini untuk melihat kartu,\nyang penting dalam pertarungan PvP.',
    'tutorial_ladder1':'Arena terbuka!\nKetuk untuk melihat.',
    'tutorial_ladder2':'Ketuk untuk masuk ke Pertandingan Peringkat.',
    'tutorial_ladder3':'Ketuk untuk menyegarkan daftar lawan.',
    'pass_level_to_unlock_cards':'Selesaikan tahap 3-2 untuk membuka Galeri Kartu.',
    'pass_level_to_unlock_ladder':'Selesaikan tahap 3-2 untuk membuka Pertandingan Peringkat.',
    'pass_level_to_unlock_pvp':'Selesaikan tahap 3-2 untuk membuka Arena.',
    'pvpTicket_buyDesc2':'Kesempatan gratis hari ini sudah habis. Beli voucher untuk melanjutkan tantangan.',
    'pvpTicket_buyDesc3':'Dalam %02d jam %02 menit, jumlah pertarungan gratis akan direset dan kamu mendapat satu kesempatan lagi untuk membeli voucher.',
    'pvpTicket_giftDesc0':'Selamat, kamu mendapat %d voucher. Voucher dapat digunakan untuk menantang pemain lain.',
    'pvpBtn_auto':'Otomatis', 'revive_game':'Bangkitkan Tim', 'report_revenge':'Balas Dendam', 'ladder_practice':'Duel',
    'playerID_placeHolder':'Masukkan ID lawan', 'ID':'ID',
    'toast_playerNotFind':'Pemain tidak ditemukan. Silakan coba lagi.',
    'pvp_bonus_message':'Selamat, kamu memenangkan hadiah mingguan peringkat teratas! Periksa kotak pesanmu.',
    'world_boss_desc_beholder':'Thousand Eyes adalah pasukan monster seorang diri!\nRibuan matanya menembus jiwa para hero dan dapat\nmemanggil tiruan jahat dari hero paling suci sekalipun\nuntuk bertarung melawanmu!',
    'popup_story_instruction':'Dapatkan peringkat S pada sebuah tahap untuk memperoleh Koin Goblin bonus dan membuka Sapu Otomatis.',
    'events_remain_time_0':'tersisa %d menit', 'events_remain_time_1':'tersisa %d jam', 'events_remain_time_2':'tersisa %d hari',
    'events_add_up_total_spent':'%s%.f', 'events_total_spent_to_get_bonus':'%s%.f',
    'events_life_gift':'Ayam BBQ x%d', 'events_life_button1':'%s ayo!',
    'pop_vip_desc':'1. Jumlah Ekspedisi harian bertambah\n\n2. Jumlah Sapu Otomatis harian bertambah\n\n3. Jatah makanan harian bertambah\n\n4. Kesempatan menukar Koin Goblin hijau bertambah',
    'heroHireTitle':'Hero-',
})

# Translation dictionaries for proper nouns/names, descriptions and dialogues.
TIPS = [
'Saat orang-orangan sawah mati, ia akan melepaskan gagak iblis! Kamu harus mengalahkan gagak-gagak itu untuk menuntaskannya.',
'Goblin pengebom akan meledak saat dikalahkan dan melukai semua yang berada di dekatnya.',
'Sebagian musuh sangat kuat, tetapi memiliki kelemahan. Kalahkan mereka secepatnya!',
'Waspadalah terhadap Morocyclops!', 'Morocyclops pemalu dan suka menyendiri.',
'Tetap waspada! Cacing pasir dapat menyerang sasaran dalam urutan apa pun!',
'Pasir hisap tidak melukai hero, tetapi membuat mereka tidak bisa bergerak.',
'Setelah cacing pasir menggali pasir, bersiaplah menghadapi bahaya!',
'Karena perang baru-baru ini, banyak jasad orc dan manusia terkubur di bawah pasir.',
'Hantaman palu Komandan Orc sangat kuat.',
'Dukun Orc meningkatkan kecepatan serangan semua sekutunya.',
'Raungan menandakan bahaya sudah dekat!',
'Bagi orc, membunuh serigala dengan tangan kosong adalah ujian kedewasaan. Berani mencoba?',
'Totem batu bukan hanya sekeras batu; totem ini juga memberi pertahanan kuat kepada petarung berotot!',
'Saat Tetua Elf menggunakan mantra pelindung, jangan sia-siakan tenagamu untuk menyerang mereka.',
'Gunakan serangan jarak jauh untuk mengalahkan Elf; mereka dapat berpindah tempat seketika.',
'Hancurkan kantong tanaman anggur vampir untuk menyelamatkan hero yang ditawan.',
'Waspadai Incendrak yang kelaparan, jangan sampai kamu menjadi santapan berikutnya.',
'Konon, gunung es adalah tempat beristirahat Leviathan.',
'Apa yang dibicarakan Tyler muda dengan Jenderal malang itu?',
'Hati-hati terhadap mantra Perubahan Wujud sang penyihir.',
'Kota Astor adalah kota terpenting bagi David.',
'Jenderal malang',
'Waspadai perisai bos! Perisai itu dapat memantulkan hampir semua jenis kerusakan!',
'Gelembung berdesis, iblis berlipat ganda; selama satu masih hidup, keduanya membawa masalah.',
'Iblis itu licik; mungkin kamu sedang ditipu!',
'Gunakan hero paling tangguh untuk melindungi hero yang lebih rentan.',
'Saat mengamuk, semua mantra Berserker menjadi lebih kuat.',
'Imam wanita dapat menyembuhkan sekutu.',
'Saat Uskup menciptakan aura, efek tambahan akan langsung aktif.',
'Kamu hanya mendapat bonus emas jika memilih mantra pasif “Pemburu Emas” dan pencurimu selamat dari pertarungan.',
'Semakin banyak poin tempur yang dimiliki, semakin efektif mantramu.',
'Perapal memiliki banyak mantra kuat. Lepaskan semuanya kepada musuh terkuatmu.',
'Ke mana pun panah Ranger jatuh, anjing pemburunya akan menyusul.',
'Jangan lupa mengambil bonus login harian!',
'Jika perlu memasang ulang game, gunakan fitur “Pulihkan Pembelian” di “Pengaturan” untuk memulihkan konten premium.',
'Promosi gila selalu menghadirkan kejutan.',
'Misi harian memberimu banyak hadiah Kristal.',
'Perhatikan syarat kemenangan pada misi harian.',
'Setelah misi selesai, tersedia banyak hadiah.',
'Poin Tantangan Bos dapat ditukar dengan aksesori langka!',
'Semakin besar total kerusakan yang kamu berikan kepada BOS, semakin banyak poin yang didapat.',
'Hanya dengan bekerja sama semua pemain bisa mengalahkan BOS DUNIA!',
'Rahasia skor tinggi: gunakan peningkat sebelum bertarung dan kuasai skill yang kuat.',
'Poin Peringkat dapat ditukar dengan benda langka!',
'Gunakan kartu bidik untuk menentukan sasaran. Seret kartunya dan cobalah!',
'Semakin tinggi tingkat kartu, semakin kuat efeknya.',
'Rahasia kemenangan peringkat: susun tim dengan tepat, lalu gunakan skill dan kartu secara bijak.',
'Kamu dapat menentukan siapa yang menantangmu.',
'Kamu dapat menonton video pertandingan peringkat melalui antarmuka laporan perang.',
'Menonton video pertarungan dapat membantumu memahami taktik lawan.',
'Setiap pemain mendapat satu kesempatan reset Ekspedisi setiap hari.',
'Mengembangkan hero cadangan dapat mencegah kekurangan personel dalam Ekspedisi.',
'Berapa banyak harta yang ada di peti Ekspedisi?',
'Pengelolaan hero yang tepat akan memudahkan pertarungan.',
'Merekrut hero kuat akan meningkatkan kekuatan tim secara drastis.',
'Gerak Lambat saat menyeret: waktu melambat sesaat ketika kamu memberi perintah kepada hero.',
'Gerak Lambat saat menyeret: waktu melambat sesaat ketika kamu memberi perintah kepada hero.',
'Hero yang dikendalikan AI akan menggunakan mantra secara otomatis.',
'Kamu dapat menyeret hero yang dikendalikan AI untuk memindahkannya.',
'Pelajari bakat agar hero dapat bangkit menjadi lebih kuat.',
'Setelah bangkit, hero mendapat banyak bonus dan sebuah skill baru!',
'Skill inisiatif hero dapat ditingkatkan dengan mempelajari bakat.',
'Buka ruang inventaris tambahan untuk menyimpan lebih banyak perlengkapan.',
'Ada enam tingkat kualitas perlengkapan, ditandai warna putih, hijau, biru, ungu, jingga, dan merah.',
'Bagikan pencapaianmu di Facebook untuk mendapatkan hadiah.',
'Kumpulkan 5 Koin Goblin, lalu putar Roda Keberuntungan untuk berkesempatan mendapat benda langka.',
'Coba ketuk dua kali untuk mempelajari bakat baru.',
'Jangan lupa menyegarkan daftar barang di toko.',
'Terlalu banyak perlengkapan tak berguna? Coba Jual Massal.',
'Terjebak di suatu tahap? Ulangi tahap sebelumnya untuk mengumpulkan hadiah.',
'Terjebak? Cobalah merekrut hero baru, mempelajari bakat, atau meningkatkan perlengkapan.'
]

HERO_NAMES = ['Prajurit Eric','Paladin Sir Potato','Berserker Crazy Hands','Imam Daisy','Pendeta Agung Mother Superior','Uskup Halo Haley','Pencuri Jacob','Pembunuh Marcus','Penjahat Scar','Master Sophia','Master Cahaya Winky','Penyihir Kegelapan Sianoid','Penembak Jitu Bran','Ranger Sang Pawang','Musketeer Gerilya']
HERO_SHORT = ['Eric','Sir Potato','Crazy Hands','Daisy','Mother Superior','Halo Haley','Jacob si Pencuri','Marcus','Scar','Sophia','Winky','Sianoid','Bran','Sang Pawang','Gerilya']
HERO_DESC = [
'Eric dahulu adalah komandan Pengawal Kerajaan. Para prajurit mengenalnya karena selalu bergegas menuju tempat yang paling berbahaya.\n“Setiap goblin yang kubasmi berarti satu sekutu terselamatkan!”',
'Kekuatan Sir Potato bukan berasal dari tubuh, melainkan dari keyakinan. Hubungannya dengan kuasa ilahi memungkinkannya melindungi sekutu dan menjatuhkan hukuman kepada musuh.\n“Keadilan bukan tentang apa yang kau inginkan, tetapi tentang apa yang benar.”',
'Belati beterbangan dari kedua tangannya dan meninggalkan luka lebih dari sekadar goresan! Saat terluka, Crazy Hands menjadi semakin ganas dengan daya serang yang mengerikan.\n“Kau belum benar-benar hidup jika belum pernah terluka!”',
'Suster Daisy adalah biarawati misionaris di garis depan. Ia ahli merawat dan mendukung sekutu yang terluka.\n“Aku tidak lahir kemarin; aku lahir kembali kemarin!” — Daisy',
'Tugas imam adalah menyembuhkan yang sakit, tetapi Mother Superior mampu menghidupkan kembali hero yang gugur agar dapat bertempur lagi.\n“Jangan sentuh aku!” — Mother Superior',
'Halo Haley menggunakan cahaya untuk memperkuat kemampuan hero. Ia menciptakan peluang bagi sekutu dalam pertempuran dan memanggil bantuan malaikat saat dibutuhkan.\n“Cahaya dunia adalah hati manusia!” — Halo Haley',
'Jacob adalah pencuri lincah dengan serangan eksplosif yang patut diwaspadai. Ia menyukai segala sesuatu yang berkilau seperti emas.\n“Uang membuat hati semakin terpikat!” — Jacob si Pencuri',
'Bersembunyi dalam bayangan, Marcus melancarkan serangan mematikan kepada musuh yang lengah. Serangannya dari kegelapan menebar ketakutan.\n“Kau bahkan tidak menyadari potongan rambut baruku, kan?” — Marcus',
'Scar mampu menyerang banyak musuh sekaligus. Ia mengumpulkan poin tempur lalu melepaskannya untuk menghasilkan kerusakan besar.\n“Pisauku sudah berada di punggungmu.” — Scar',
'Di balik topinya terdapat lambang berbentuk kilat di dahinya. Saat kecil, ia dikirim untuk mempelajari ilmu sihir.\n“Perenungan akan memberimu jawaban yang kau cari.” — Master Sophia',
'Penguasaan mantra Winky memungkinkannya memberi kerusakan besar kepada banyak musuh sekaligus. Ia juga dapat membuat musuh kuat kehilangan daya.\n“Aku datang, lalu menghilang.” — Winky',
'Ahli sihir gelap ini gemar menyiksa dan melahap musuhnya.\n“Bergabunglah dengan sisi gelap.” — Sianoid',
'Bran adalah pemburu terampil yang dapat mengenai sasaran jauh dengan busurnya.\n“Ada yang salah dengan panah itu!” — Bran',
'Pawang ini ahli melukai musuh jarak jauh dengan tembakan yang terlalu cepat untuk dilihat. Anjingnya pun ganas dan kejam.\n“Jika aku sedang baik hati, titik tengah sasaran adalah kepalamu.” — Sang Pawang',
'Prajurit gerilya ini menyerang dari jauh dengan kemampuan menembak legendaris. Ia mahir menggunakan berbagai senjata api dan amunisi.\n“Peluru tak punya mata.” — Gerilya'
]

ACTIVE_NAMES = ['Tanpa Gentar','Ejekan','Pukulan Keras','Cahaya Surgawi','Hentakan Perang','Penghakiman Ilahi','Hantaman Perisai','Perisai Suci','Amukan','Lompatan Liar','Auman Singa','Angin Puyuh','Lepaskan Amarah','Aura Penyembuhan','Perlindungan','Penebusan','Keselamatan','Pengumpulan Jiwa','Tebusan','Wujud Malaikat','Kebangkitan','Aura Keberanian','Aura Berkah','Aura Keteguhan','Aura Kelincahan','Malaikat Pelindung','Sayatan Mematikan','Lempar Belati','Penghancur Zirah','Menghilang','Sayatan Akurat','Sayat Tenggorokan','Pembunuhan Senyap','Amukan Darah','Pedang Bayangan','Peruntuh','Penghancur Zirah','Serangan Bayangan','Pedang Pengisap Darah','Sambaran Es','Meteor','Kilat','Kulit Batu','Naga Api','Nova Es','Ledakan Badai','Kecerdasan Gaib','Daya Tahan Vampir','Ubah Jadi Alpaka','Wabah','Penuaan','Bola Kematian','Tembakan Penembus','Ledakan Dahsyat','Tembakan Mematikan','Panah Es','Panah Beracun','Panah Peledak','Hujan Panah','Panah Apollo','Tembakan Tiga Kali','Amunisi Pembakar','Granat','Senapan Gentel','Isi Ulang','Pukulan Berkekuatan']
PASSIVE_NAMES = ['Ketangguhan','Daya Tahan','Karunia Ilahi','Dewa Perang','Hasrat Kematian','Haus Darah','Berkah','Bantuan Ilahi','Gairah','Penyembuhan Terikat','Penyiksaan','Dukungan','Pemburu Emas','Penguasa Kematian','Akurasi','Fokus','Keunggulan Tempur','Master Kombo','Kebijaksanaan','Langkah Eter','Pembekuan Mendalam','Ledakan Petir','Daya Guna','Tangan Beracun','Tanda Pemburu','Pengalihan','Anjing Penjaga','Sensasi Berburu','Magasin Diperpanjang','Pelepas Panas']
SUPERIOR_NAMES = [
'Peningkatan Cahaya Surgawi','Peningkatan Hentakan Perang','Peningkatan Penghakiman Ilahi','Peningkatan Hantaman Perisai','Peningkatan Perisai Suci','Peningkatan Amukan','Peningkatan Lompatan Liar','Peningkatan Auman Singa','Peningkatan Angin Puyuh','Peningkatan Lepaskan Amarah','Peningkatan Keselamatan','Peningkatan Pengumpulan Jiwa','Peningkatan Tebusan','Peningkatan Wujud Malaikat','Peningkatan Kebangkitan','Peningkatan Aura Keberanian','Peningkatan Aura Berkah','Peningkatan Aura Keteguhan','Peningkatan Aura Kelincahan','Peningkatan Malaikat Pelindung','Peningkatan Menghilang','Peningkatan Sayatan Akurat','Peningkatan Sayat Tenggorokan','Peningkatan Pembunuhan Senyap','Peningkatan Amukan Darah','Peningkatan Pedang Bayangan','Peningkatan Peruntuh','Peningkatan Penghancur Zirah','Peningkatan Serangan Bayangan','Peningkatan Pedang Pengisap Darah','Peningkatan Kulit Batu','Peningkatan Naga Api','Peningkatan Nova Es','Peningkatan Ledakan Badai','Peningkatan Kecerdasan Gaib','Peningkatan Daya Tahan Vampir','Peningkatan Ubah Jadi Alpaka','Peningkatan Wabah','Peningkatan Penuaan','Peningkatan Bola Kematian','Peningkatan Panah Es','Peningkatan Panah Beracun','Peningkatan Panah Peledak','Peningkatan Hujan Panah','Peningkatan Panah Apollo','Peningkatan Tembakan Tiga Kali','Peningkatan Amunisi Pembakar','Peningkatan Granat','Peningkatan Senapan Gentel','Peningkatan Isi Ulang','Peningkatan Tanpa Gentar','Peningkatan Ejekan','Peningkatan Hantaman','Peningkatan Penyembuhan Tim','Peningkatan Perisai','Peningkatan Pemulihan','Peningkatan Serangan Jahat','Peningkatan Penghancur Zirah','Peningkatan Pemotong Terbang','Peningkatan Sambaran Es','Peningkatan Meteor','Peningkatan Kilat','Peningkatan Tembakan Penembus','Peningkatan Ledakan Dahsyat','Peningkatan Serangan Jatuh dan Penghancur Zirah'
]

ACTIVE_DESC = [
'Mengurangi kerusakan yang diterima sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Memancing amarah musuh agar mereka menyerang prajurit ini. (Waktu penggunaan ulang: %Ds)',
'Serangan kuat yang memberikan %P kerusakan biasa dan %D kerusakan langsung kepada sasaran. (Waktu pemulihan: %D detik)',
'Memanggil pancaran cahaya surgawi untuk menyembuhkan sekutu yang paling terluka. (Waktu penggunaan ulang: %Ds)',
'Melompat dan menghantam tanah, mengurangi dampak serangan musuh sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Mengurangi HP musuh saat ini sebesar %P. Jika keberuntungan berpihak padamu (%P peluang), serangan memberikan kerusakan %D kali lipat atau %D kali kekuatan seranganmu. (Waktu penggunaan ulang: %Ds)',
'Menghantam musuh dengan perisai hingga jatuh selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Menciptakan aura suci selama %D detik yang menyerap %P kerusakan dari serangan musuh. (Waktu penggunaan ulang: %Ds)',
'Mengorbankan %P HP untuk memperoleh tambahan %P kekuatan serangan dan %P kecepatan serangan selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Melompat ke sasaran dan mendarat dengan kekuatan dahsyat, menyerang musuh di dekatnya. Saat mengamuk, semua musuh yang terkena akan terjatuh. (Waktu penggunaan ulang: %Ds)',
'Mengaum keras hingga musuh kabur selama %D detik. Saat mengamuk, mereka kabur %P lebih lama. (Waktu penggunaan ulang: %Ds)',
'Berputar seperti badai bilah baja dan melukai semua musuh di sekitar. Saat mengamuk, kerusakan bertambah %P. (Waktu penggunaan ulang: %Ds)',
'Melepaskan amarah dan menghantam musuh sebanyak %D kali berturut-turut, atau %D kali saat mengamuk. (Waktu penggunaan ulang: %Ds)',
'Menciptakan aura penyembuhan yang memulihkan sedikit HP semua hero. (Waktu penggunaan ulang: %Ds)',
'Meningkatkan zirah sekutu sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Memulihkan HP sekutu selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Seketika memulihkan %P HP sekutu. (Waktu penggunaan ulang: %Ds)',
'Menyerap HP dari semua jiwa di medan perang dan memberikannya kepada sasaran. Jumlah yang dipulihkan setara dengan %P kekuatan penyembuhan. (Waktu penggunaan ulang: %Ds)',
'Memberkati sekutu selama %D detik dan memulihkan HP sebesar %P setiap detik. (Waktu penggunaan ulang: %Ds)',
'Berubah menjadi malaikat, meningkatkan efek mantra penyembuhan sebesar %P dan mengurangi kerusakan yang diterima sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Mengorbankan sebagian besar HP pendeta wanita untuk menghidupkan kembali sekutu yang baru gugur dengan %P HP. (Waktu penggunaan ulang: %Ds)',
'Melukai semua musuh sedikit dan meningkatkan kekuatan serangan semua sekutu sebesar %P. (Waktu penggunaan ulang: %Ds)',
'Menyembuhkan sedikit HP semua sekutu dan meningkatkan kecepatan pemulihan mereka sebesar %P. (Waktu penggunaan ulang: %Ds)',
'Meningkatkan zirah sekutu sebesar %P dan membuat semua musuh terpana selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Seketika meningkatkan kecepatan merapal semua sekutu selama %D detik serta meningkatkan kecepatan gerak sebesar %P. (Waktu penggunaan ulang: %Ds)',
'Memanggil malaikat pelindung untuk menyembuhkan sekutu dengan HP terendah selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Melancarkan satu pukulan dahsyat ke arah musuh sasaran. (Waktu penggunaan ulang: %Ds)',
'Melemparkan pisau ke semua musuh di depan, menimbulkan kerusakan besar. (Waktu penggunaan ulang: %Ds)',
'Mengurangi zirah sasaran sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Menghilang selama %D detik dan tidak menerima kerusakan kecuali saat menyerang atau merapal mantra. HP pulih perlahan. (Waktu penggunaan ulang: %Ds)',
'Menyayat celah zirah musuh sehingga zirahnya menjadi 0% untuk satu serangan. (Waktu penggunaan ulang: %Ds)',
'Menimbulkan kerusakan besar. Jika HP musuh berada di bawah %P, kerusakannya menjadi dua kali lipat. (Waktu penggunaan ulang: %Ds)',
'Mencoba membunuh sasaran secara diam-diam. Semakin banyak HP sasaran yang hilang, semakin kuat seranganmu, hingga maksimum 100%. (Waktu penggunaan ulang: %Ds)',
'Melancarkan serangkaian serangan secepat kilat ke satu sasaran. (Waktu penggunaan ulang: %Ds)',
'Bergerak senyap seperti bayangan dan menyerang %D kali, memperoleh tambahan %D poin tempur. (Waktu penggunaan ulang: %Ds)',
'Semakin kuat musuh, semakin keras ia jatuh! Musuh yang lebih kuat menerima lebih banyak kerusakan. Memperoleh tambahan %D poin tempur. (Waktu penggunaan ulang: %Ds)',
'Menerobos zirah musuh; semakin tebal zirahnya, semakin besar kerusakan yang ditimbulkan. Memperoleh tambahan %D poin tempur. (Waktu penggunaan ulang: %Ds)',
'Tiba-tiba muncul di belakang sasaran dan memberi serangan kritis, membuatnya terpana selama %D detik. Menghabiskan semua poin tempur; setiap poin menambah durasi pingsan %D detik. (Waktu penggunaan ulang: %Ds)',
'Menggunakan semua poin tempur untuk mengisap nyawa musuh dan memulihkan si penjahat. Setiap poin meningkatkan kerusakan dan efek sebesar %P. (Waktu penggunaan ulang: %Ds)',
'Menusuk musuh dengan sambaran es, menimbulkan sedikit kerusakan dan memperlambat sasaran sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Memanggil meteor yang menimbulkan kerusakan besar kepada semua musuh di area ledakan. (Waktu penggunaan ulang: %Ds)',
'Menyambar musuh dengan kilat, menjatuhkannya dan menimbulkan kerusakan besar. (Waktu penggunaan ulang: %Ds)',
'Memanggil perisai dengan HP sebesar %P dari total HP penyihir. Perisai menerima kerusakan sebagai pengganti penyihir selama %Ds atau sampai hancur. (Waktu penggunaan ulang: %Ds)',
'Memanggil naga api raksasa untuk membakar musuh! (Waktu penggunaan ulang: %Ds)',
'Membekukan musuh hingga ke tulang dan memperlambat semua musuh di sekitar sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Menyambar tiga musuh dengan trisula dari langit! (Waktu penggunaan ulang: %Ds)',
'Meningkatkan kekuatan serangan sekutu sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Mengisap nyawa musuh, mengurangi HP mereka dan menambah HP milikmu. (Waktu penggunaan ulang: %Ds)',
'Mengubah musuh menjadi alpaka selama %D detik. Alpaka tidak dapat menyerangmu, tetapi kamu tetap dapat menyerangnya. (Waktu penggunaan ulang: %Ds)',
'Menyebarkan wabah yang menginfeksi sasaran dan musuh di dekatnya, mengurangi HP selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Membuat musuh menua dan pikun, mengurangi semua atribut sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Memanggil lima bola sihir hitam yang melayang menuju sasaran lalu meledak, menimbulkan kerusakan besar. (Waktu penggunaan ulang: %Ds)',
'Mengenai titik lemah sasaran dengan tepat dan mengabaikan %P zirahnya. (Waktu penggunaan ulang: %Ds)',
'Menghantam musuh dengan ledakan kuat hingga terpental jauh. (Waktu penggunaan ulang: %Ds)',
'Menembakkan peluru mematikan. Selama %D detik, musuh hanya menerima %P efek dari mantra penyembuhan. (Waktu penggunaan ulang: %Ds)',
'Menimbulkan sedikit kerusakan dan memperlambat musuh sebesar %P selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Meracuni musuh dan menimbulkan kerusakan selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Menembakkan peluru peledak yang pecah dan turut mengenai sasaran di dekatnya. (Waktu penggunaan ulang: %Ds)',
'Melepaskan rentetan panah, satu untuk setiap musuh, dan menimbulkan kerusakan besar pada masing-masing sasaran. (Waktu penggunaan ulang: %Ds)',
'Menembakkan panah sihir yang menjatuhkan dan melukai semua musuh di jalurnya. (Waktu penggunaan ulang: %Ds)',
'Menghantam musuh tiga kali dengan rentetan tembakan mematikan. (Waktu penggunaan ulang: %Ds)',
'Amunisi pembakar menyala dan membakar area selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Melempar granat ke kelompok musuh—awas, granat meledak! (Waktu penggunaan ulang: %Ds)',
'Senapan gentel memiliki jangkauan terbatas, tetapi menimbulkan kerusakan besar dan menjatuhkan musuh selama %D detik. (Waktu penggunaan ulang: %Ds)',
'Mengisi ulang seketika. Gunakan kembali mantra lain tanpa menunggu! (Waktu penggunaan ulang: %Ds)',
'Memanggil Hercules Sang Petinju untuk menghantam musuh di barisan depan, mengurangi serangan sebesar %P dan zirah sebesar %P selama %D detik. (Waktu pemulihan: %D detik)'
]

PASSIVE_DESC = [
'Meningkatkan total HP prajurit sebesar %P. (Mantra pasif)',
'Meningkatkan ketahanan terhadap serangan musuh sebesar %P. (Mantra pasif)',
'Meningkatkan HP, kekuatan serangan, dan zirah Paladin sebesar %P. (Mantra pasif)',
'Setiap HP berkurang %1, zirah meningkat sebesar %D%. (Mantra pasif)',
'Setiap HP berkurang %1, kekuatan serangan meningkat sebesar %D%. (Mantra pasif)',
'Setiap HP berkurang %1, kecepatan serangan meningkat sebesar %D%. (Mantra pasif)',
'Meningkatkan zirah sekutu sebesar %P setiap %D detik. (Mantra pasif)',
'Memperkuat serangan sekutu sebesar %P setiap %D detik. (Mantra pasif)',
'Menyembuhkan sasaran dan juga memulihkan sekutu di dekatnya sebesar %P dari kekuatan penyembuhan. (Mantra pasif)',
'Saat menyembuhkan orang lain, kamu juga menyembuhkan diri sendiri sebesar %P dari kekuatan penyembuhan. (Mantra pasif)',
'Saat menggunakan penyembuhan otomatis, semua musuh di sekitar sasaran menerima kerusakan sebesar %P. (Mantra pasif)',
'Meningkatkan efektivitas penyembuhan otomatis sebesar %P. (Mantra pasif)',
'Mencuri emas dari musuh sehingga emas yang diperoleh setelah menang meningkat sebesar %P. (Mantra pasif)',
'Meningkatkan kerusakan serangan sebesar %P. (Mantra pasif)',
'Semua mantra memiliki peluang %P untuk menimbulkan kerusakan dua kali lipat. (Mantra pasif)',
'Kecepatan serangan ke satu sasaran meningkat bertahap hingga %P. (Mantra pasif)',
'Meningkatkan batas maksimum poin tempur dari 5 menjadi 7. (Mantra pasif)',
'Mendapatkan satu poin tempur setiap %D detik. (Mantra pasif)',
'Menguasai mantra dan meningkatkan kerusakannya sebesar %P. (Mantra pasif)',
'Berpindah seketika ke lokasi mana pun di medan perang. (Mantra pasif)',
'Sihir es memperlambat musuh dan meningkatkan %P. (Skill pasif)',
'Ledakan petir memanggil satu sambaran petir tambahan. (Skill pasif)',
'Setiap merapal mantra, muncul bola energi sihir yang meningkatkan serangan sebesar %P selama %D detik. (Mantra pasif)',
'Ada peluang %P untuk menginfeksi musuh dengan wabah saat menyerangnya, menimbulkan kerusakan selama %D detik. (Mantra pasif)',
'Mengurangi zirah musuh sebesar %P selama %D detik. (Mantra pasif)',
'Mengalihkan perhatian musuh agar menyerang sekutumu yang paling kuat. (Mantra pasif)',
'Memanggil anjing untuk membantumu!',
'Ada peluang %P agar kamu dapat merapal mantra lagi tanpa menunggu. (Mantra pasif)',
'Meningkatkan kecepatan menembak sebesar %P.',
'Meningkatkan kecepatan merapal mantra sebesar %P. (Mantra pasif)'
]

SUPERIOR_DESC = [
'✦ Efek Cahaya Surgawi meningkat pesat!',
'✦ Kerusakan serangan musuh berkurang sekitar %P.',
'✦ Waktu penggunaan ulang Penghakiman Ilahi menjadi %D detik.',
'✦ Durasi menjatuhkan musuh meningkat menjadi %D detik.',
'✦ Aura menyerap dan memberikan %P dari kerusakan yang diterima.',
'✦ Tidak perlu lagi mengorbankan HP.',
'✦ Efek mantra ini menjangkau semua musuh.',
'✦ Musuh juga melambat sebesar %P selama %D detik.',
'✦ Kerusakan Angin Puyuh dikalikan %O.',
'✦ Waktu penggunaan ulang berkurang menjadi %D detik.',
'✦ Memulihkan %P HP sekutu.',
'✦ Jumlah HP yang diserap dan diberikan meningkat menjadi %P dari kekuatan penyembuhan.',
'✦ Manfaatnya menjadi dua kali lipat dan durasi pingsan berkurang setengah.',
'✦ Menjadi tak terkalahkan selama berada dalam Wujud Malaikat.',
'✦ Waktu penggunaan ulang berkurang menjadi %D detik.',
'✦ Meningkatkan kekuatan serangan semua sekutu sebesar %P.',
'✦ Jumlah HP yang dipulihkan meningkat drastis.',
'✦ Durasi stun semua musuh bertambah menjadi %D detik.',
'✦ Efek peningkatan kecepatan merapal berlangsung selama %D detik.',
'✦ Durasi Malaikat Pelindung bertambah menjadi %D detik.',
'✦ Saat menghilang, HP pulih dengan cepat.',
'✦ Selain itu, musuh akan terpana selama %D detik.',
'✦ Jika HP sasaran kurang dari %P, kerusakan dikalikan %P.',
'✦ Kerusakan mantra ini dikalikan %O.',
'✦ Waktu penggunaan ulang berkurang menjadi %D detik.',
'✦ Kerusakan mantra ini dikalikan %O.',
'✦ Mengurangi kekuatan serangan musuh sebesar %P selama %D detik.',
'✦ Mengurangi zirah musuh sebesar %P selama %D detik.',
'✦ Setiap poin tempur membuat musuh terpana selama %D detik.',
'✦ Setiap poin tempur meningkatkan kerusakan dan efek sebesar %P.',
'✦ Daya tahan perisai meningkat menjadi %P dari total HP penyihir.',
'✦ Intensitas api naga meningkat drastis.',
'✦ Efek mantra ini menjangkau semua musuh.',
'✦ Jumlah sambaran petir meningkat menjadi %D.',
'✦ Durasi efek meningkat menjadi %D detik.',
'✦ Jumlah nyawa yang diserap meningkat drastis.',
'✦ Musuh tetap menjadi alpaka selama %D detik.',
'✦ Wabah menjadi jauh lebih parah.',
'✦ Pengurangan atribut musuh meningkat menjadi %P.',
'✦ Waktu penggunaan ulang berkurang menjadi %D detik.',
'✦ Kerusakan tetap sama, tetapi musuh melambat sebesar %P.',
'✦ Kekuatan racun meningkat drastis.',
'✦ Musuh juga terjatuh selama %D detik.',
'✦ Kerusakan meningkat menjadi %D kali kekuatan serangan.',
'✦ Kerusakan Panah Apollo meningkat drastis.',
'✦ Musuh juga terpana selama %D detik.',
'✦ Semua musuh yang terkena api melambat sebesar %P.',
'✦ Waktu penggunaan ulang berkurang menjadi %D detik.',
'✦ Kerusakan meningkat drastis.',
'✦ Waktu penggunaan ulang berkurang menjadi %D detik.',
'✦ Efek pertahanan Tanpa Gentar meningkat hingga %P.',
'✦ Musuh yang terkena kehilangan %P zirah dan terus melambat selama %D detik.',
'✦ Kerusakan hantaman meningkat hingga %O kali lipat.',
'✦ Jumlah penyembuhan tim meningkat hingga %O kali lipat.',
'✦ Bonus zirah dari perisai meningkat menjadi %P.',
'✦ Durasi penyembuhan meningkat menjadi %D detik.',
'✦ Kerusakan Serangan Jahat meningkat hingga %O kali lipat.',
'✦ Efek penghancuran zirah meningkat menjadi %P.',
'✦ Kerusakan Pemotong Terbang meningkat hingga %O kali lipat.',
'✦ Memperlambat gerakan dan mengurangi kecepatan serangan musuh sebesar %P.',
'✦ Kerusakan Meteor meningkat hingga %O kali lipat.',
'✦ Kerusakan Kilat meningkat hingga %O kali lipat.',
'✦ Tembakan Penembus mengabaikan pertahanan musuh hingga %P.',
'✦ Kerusakan Ledakan Dahsyat meningkat hingga %O kali lipat.',
'✦ Serangan jatuh ditingkatkan dan Penghancur Zirah mengurangi serangan musuh tambahan sebesar %P; efek penghancuran zirah meningkat menjadi %P.'
]

GEAR_SKILL_DESC = [
'✦ Peluang %P untuk menghasilkan kerusakan atau penyembuhan 1,5 kali lipat.',
'✦ Mempercepat pemulihan HP otomatis sebesar %P per detik.',
'✦ Meningkatkan kecepatan gerak sebesar %P.',
'✦ Saat menyerang, ada peluang %P untuk membuat musuh ketakutan dan kabur selama %D detik.',
'✦ Saat menyerang, ada peluang %P untuk membuat musuh terpana selama %D detik.',
'✦ Saat menyerang, ada peluang %P untuk menjatuhkan musuh selama %D detik.',
'✦ Saat menyerang, ada peluang %P untuk mengubah musuh menjadi alpaka selama %D detik.',
'✦ Saat menyerang, ada peluang %P untuk memperlambat musuh sebesar %P selama %D detik.',
'✦ Seranganmu menyerap nyawa sebesar %P.',
'✦ Saat menyerang, menimbulkan kerusakan sebesar %P kepada musuh di dekat sasaran.',
'✦ Saat menyerang, ada peluang %P untuk menyambar musuh dengan petir dan menimbulkan kerusakan %P.',
'✦ Saat menyembuhkan, ada peluang %P untuk meningkatkan serangan sasaran sebesar %P selama %D detik.',
'✦ Saat menyembuhkan, ada peluang %P untuk meningkatkan zirah sasaran sebesar %P selama %D detik.',
'✦ Saat menyembuhkan, ada peluang %P untuk mempercepat perapalan mantra sasaran sebesar %D detik.',
'✦ Saat menyembuhkan, ada peluang %P untuk membuat semua mantra sasaran siap digunakan.',
'✦ Saat menyembuhkan, ada peluang %P untuk mempercepat perapalan mantramu sendiri sebesar %D detik.',
'✦ Saat merapal mantra, ada peluang %P untuk langsung dapat menggunakannya kembali.',
'✦ Saat mengalahkan musuh, pulihkan %P HP milikmu.',
'✦ Saat diserang, ada peluang %P untuk tidak menerima kerusakan.',
'✦ Saat diserang, balas dengan kerusakan sebesar %P dari daya serang penyerang.',
'✦ Saat diserang, ada peluang %P untuk membuat penyerang terpana selama %D detik.',
'✦ Menambah HP sebesar %P.', '✦ Meningkatkan kekuatan serangan sebesar %P.', '✦ Meningkatkan zirah sebesar %P.',
'✦ Saat HP di bawah %P, meningkatkan kekuatan serangan sebesar %P.',
'✦ Saat HP di bawah %P, meningkatkan zirah sebesar %P.',
'✦ Meningkatkan kecepatan merapal mantra sebesar %P.',
'✦ Menambah pengalaman yang diperoleh setelah setiap pertarungan sebesar %P.',
'✦ Menambah emas yang diperoleh setelah setiap pertarungan sebesar %P.',
'✦ Menambah Kristal yang diperoleh setelah setiap pertarungan sebesar %P.',
'✦ Meningkatkan kecepatan serangan sebesar %P.',
'✦ Peluang %P agar hero kebal terhadap efek terpana.',
'✦ Peluang %P agar hero kebal terhadap efek jatuh.',
'✦ Peluang %P agar hero kebal terhadap rasa takut.',
'✦ Peluang %P agar hero kebal terhadap perubahan menjadi alpaka.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D dan zirah sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Berkah Natal: meningkatkan serangan pemakai sebesar tingkat pembawa x%D.',
'✦ Saat diserang, ada peluang %P untuk mengubah kerusakan serangan itu menjadi pemulihan HP hero.',
'✦ Meningkatkan serangan pemakai sebanyak %d tingkat dan zirah pemakai sebanyak %d tingkat.',
'✦ Meningkatkan kekuatan serangan pemakai.', '✦ Meningkatkan kekuatan serangan pemakai.', '✦ Meningkatkan kekuatan serangan pemakai.',
'✦ Meningkatkan kekuatan serangan pemakai.', '✦ Meningkatkan kekuatan serangan pemakai.', '✦ Meningkatkan kekuatan serangan pemakai.',
'✦ Meningkatkan zirah. Saat terluka, ada peluang %P untuk meningkatkan zirah sebesar %P selama %D detik. Efek dapat ditumpuk.',
'✦ Meningkatkan zirah. Saat terluka, ada peluang %P untuk meningkatkan serangan sebesar %P selama % D detik. Efek dapat ditumpuk.',
'✦ Meningkatkan zirah. Saat terluka, ada peluang %P untuk meningkatkan kecepatan gerak sebesar %P dan kecepatan serang sebesar %P selama %D detik. Efek dapat ditumpuk.',
'✦ Meningkatkan serangan %P, zirah %P, dan darah/HP %P.'
]

CARD_SKILL_DESC = [
'Memunculkan duri es tajam di bawah kaki musuh, melukai semua musuh di area jangkauan (faktor kerusakan: %P). Memperlambat sebesar %P selama %D detik.',
'Memanggil sulur mematikan dari atas. HP 3 musuh acak berkurang sebesar %P.',
'Mengelilingi unitmu dengan ledakan energi yang melukai musuh di dekatnya (faktor kerusakan: %P).',
'Menimbulkan kerusakan kepada satu musuh (faktor kerusakan: %P); jika HP musuh di bawah %P, musuh langsung dikalahkan.',
'Membebaskan hero dari takut, pusing, jatuh, atau perubahan menjadi alpaka selama %D detik.',
'Mengurangi kemampuan penyembuhan musuh sebesar %P selama %D detik.',
'Semua serangan dan penyembuhan selama %D detik menjadi serangan kritis.',
'Memanggil Morocyclops (faktor kekuatan: %P). Ia terus menyerang sampai dikalahkan. Maksimal satu Morocyclops pada satu waktu.',
'Hero musuh tidak dapat menggunakan skill selama %D detik.',
'Menahan musuh dengan tanaman pemakan manusia. Musuh yang terperangkap tidak dapat bergerak atau menyerang selama %D detik.',
'Menciptakan perisai angin selama %D detik. Penyerang di dekatnya akan terpental.',
'Menciptakan medan magnet yang menarik musuh di sekitar menuju seorang hero dan mengurangi zirah mereka sebesar %P selama %D detik.',
'Memanggil peri untuk membantu menyembuhkan hero selama %D detik (faktor penyembuhan: %P).',
'Memanggil totem petir (faktor kekuatan: %P). Totem terus menyerang sampai dihancurkan; maksimal %D totem.',
'Memanggil tim juara untuk melukai musuh (faktor kerusakan: %P) dan menjatuhkan mereka selama %D detik.',
'Memanggil totem haus darah selama %D detik untuk meningkatkan kecepatan serangan hero sebesar %P.',
'Mencegah lawan memainkan kartu selama %D detik.',
'Langsung mendapatkan %D kartu baru dengan peluang %P untuk mendapat kartu bonus.',
'Membuat lawan kehilangan 1 kartu; ada peluang %P agar semua kartunya hilang.',
'Mencuri kartu lawan dengan peluang %P untuk memperoleh kartu bonus.'
]

STORY = {
'0001':'Prajurit 1:\nBos, mengapa kita mengepel lantai?',
'0002':'Prajurit 2:\nBenar, seharusnya kita mengabdi kepada Raja Michael.',
'0003':'Eric:\nUh... kau terlalu bodoh untuk mengerti. Aku hanya berharap Guru Kun bisa menghadapi perangai buruk Raja Michael.',
'0004':'???:\nRaja Michael? Kalian seharusnya mengkhawatirkan diri sendiri!',
'0005':'Beberapa menit kemudian...',
'0006':'Daisy:\nHah? Pasukan depan sudah dihancurkan! Apa-apaan ini? Oh... yang tinggi dan kuat itu... Eric, benarkah itu kau?',
'0007':'Daisy:\nJangan! Eric, kau tidak boleh terluka! Gawat darurat! Ketuk lalu seret aku ke tubuh yang terluka.',
'0008':'Eric:\nDaisy! Kau menyelamatkanku! Hidupku milikmu... aku akan menikahimu!',
'0009':'Daisy:\nEric, kau perlu beristirahat. Pikiranmu sedang kacau.',
'0010':'Eric:\nTidak! Aku harus kembali ke kota untuk memberi tahu Raja Michael bahwa kita diserang. Kita harus memanggil pulang semua pasukan untuk mempertahankan kerajaan!',
'0011':'Eric:\nSeret penunjuk ke posisi mana pun untuk memberi perintah “bergerak”.',
'0012':'Eric:\nSeorang prajurit berjalan mendekat. Daisy, berdirilah di belakangku!',
'0013':'Eric:\nCepat habisi dia! Tahan lalu seret penunjuk ke arah musuh untuk menyerangnya.',
'0014':'Daisy:\nKita berdua terluka, tetapi aku punya skill penyembuhan. Ketuk lalu pilih aku.',
'0015':'Daisy:\nKetuk ikon skill di kiri atas untuk menggunakannya.',
'0016':'Daisy:\nLakukan hal yang sama agar Eric menggunakan skill-nya.',
'0017':'Enam bulan sebelumnya...',
'0101':'Daisy:\nTerlalu berbahaya. Aku tak bisa membiarkanmu pergi sendirian. Jika sesuatu yang buruk terjadi padamu, bagaimana aku bisa terus hidup?',
'0102':'Eric:\nDaisy, lima orang datang dari langit. Tak masalah! Tahukah kau bahwa aku lulusan sekolah pedang?',
'0201':'Sophia:\nDi sana! Tolong!',
'0202':'Eric:\nApa yang terjadi?',
'0203':'Sophia:\nOrang-orangan sawah ini mengejarku!',
'0204':'Daisy:\nSaat orang-orangan sawah mati, ia berubah menjadi beberapa gagak. Kita harus mengalahkan gagak-gagak itu untuk menghancurkannya.',
'0205':'Sophia:\nOh, begitu! Jadi aku tak bisa membunuhnya? Lihat, ia datang lagi!',
'0206':'Eric:\nSemuanya hati-hati! Ayo kalahkan dia.',
'0211':'Sophia:\nTerima kasih sudah menolongku!',
'0212':'Eric:\nHahaha, menghukum orang jahat memang tugasku.',
'0213':'Daisy:\nAkhir-akhir ini banyak monster bermunculan. Tidak aman berjalan sendirian; mari kita bepergian bersama!',
'0214':'Sophia:\nBaiklah! Perkenalkan, aku Sophia, seorang penyihir. Sihirku kuat, tetapi tubuhku rapuh. Tolong lindungi aku dari serangan!',
'0215':'Eric:\nTenang saja, aku akan melindungimu. Ayo berangkat.',
'0301':'Daisy:\nEric, banyak sekali musuh di sini. Bolehkah aku mengalahkan mereka sendiri?',
'0302':'Daisy:\nPertama, ketuk tombol jeda di kanan atas layar.',
'0303':'Daisy:\nLalu, ketuk tombol Otomatis di bawah avatarku.',
'0304':'Daisy:\nSekarang ketuk tombol kembali, lalu bertarunglah!',
'0305':'Daisy:\nBegitulah! Dengan pengaturan ini aku dapat menggunakan skill secara otomatis, tetapi kamu tetap bisa memberi perintah gerak dengan menyeret penunjuk.',
'0601':'Daisy:\nGawat! Para goblin merampok kota? Berani sekali mereka!',
'0602':'Eric:\nKupikir kita datang untuk membersihkan mayat goblin. Mana mayat-mayatnya?',
'0603':'Sophia:\nApa? Raja Michael menyuruh kalian membersihkan mayat goblin? Ia pasti sangat menghormati kalian!',
'0604':'Eric:\nBukan Raja Michael. Sir Mo menyuruhku membawa orang-orang ke sini.',
'0605':'Sophia:\nSir Mo? Maksudmu Mo si Gila, saudara Raja Michael?',
'0606':'Eric:\nBenar. Raja Michael sedang sakit dan Pangeran Amor masih terlalu muda, jadi Sir Mo menggantikannya.',
'1001':'Dokter Goblin:\nManusia sombong! Anakku akan memberimu mayat untuk dibersihkan. Temui MOMO si Mata Satu!',
'1002':'MOMO si Mata Satu:\nSenang bertemu denganmu... eh... MATI KALIAN, MANUSIA!',
'1003':'Tabib Goblin:\nBerhenti bicara dan mulai HANCURKAN MEREKA!',
'1004':'Daisy:\nBau busuk apa itu... Oh tidak, ternyata kakinya!',
'1101':'Eric:\nApakah itu Pangeran Amor?',
'1102':'Sophia:\nItu benar-benar Pangeran Amor! Apa yang kau lakukan di sini?!',
'1103':'Pangeran Amor:\nEric! Kenapa lama sekali? Seorang lelaki tua dibunuh Taimok, dan sekarang ia juga ingin membunuhku! Guru Kun memindahkanku ke sini dengan sihir agar bisa melindungiku.',
'1104':'Eric:\nTaimok muncul lagi! Percayalah, aku akan membawamu kembali ke kota dengan selamat. Lalu kita akan mengalahkan mereka dan membalas kematian Raja Michael!',
'1105':'Pangeran Amor:\nTunjukkan jalannya! Kita harus segera menyelamatkan Raja Michael!',
'1301':'Sophia:\nApakah ini mumi? Kelihatannya sangat tua.',
'1302':'Pangeran Amor:\nSophia! Apakah kau membawa air suci?',
'1303':'Sophia:\nAku baru hari ketiga mengikuti kursus Alkitab... aku belum bisa membuat air suci.',
'1304':'Eric:\nMinggir, biar aku yang melakukannya!',
'1601':'Pangeran Amor:\nAda banyak mumi di sekitar sini. Apakah ini kuburan massal?',
'1602':'Eric:\nDengarkan, akan kuceritakan. Bertahun-tahun lalu, Raja Michael membantu penduduk asli gurun mengalahkan monster yang menguasai wilayah ini.',
'1603':'Eric:\nNamun, selama konflik, sekelompok pembunuh orc membunuh putra kepala suku. Sang kepala suku begitu marah hingga menghancurkan negeri itu bersama semua orc, bahkan pasukannya sendiri. Kini tempat ini hanyalah tanah tandus yang terkutuk.',
'1604':'Daisy:\nApa itu? Angin? Guntur? Hujan? Cari perlindungan!',
'2001':'Sophia:\nDengan memandang bintang untuk mencari petunjuk... sepertinya kita hampir tiba di tepi gurun.',
'2002':'Pangeran Amor:\nBukankah seharusnya sekarang siang?',
'2003':'Sophia:\nItu cacing pasir! Kenapa ukurannya sebesar itu?',
'2004':'Eric:\nBukan hanya besar, ia juga bisa menggali lubang dan menciptakan pasir hisap.',
'2101':'Daisy:\nDi mana Pangeran Amor?',
'2102':'Sophia:\nDi mana Pangeran Amor? Coba kupikirkan...',
'2103':'Eric:\nKurasa Pangeran Amor dalam bahaya. Ia pasti diculik para orc! Ikuti jejak kaki ini untuk mengetahui ke mana mereka membawanya. Kita harus menemukan Pangeran Amor!',
'2501':'Daisy:\nOrc, mengapa kalian mengorbankan manusia?',
'2502':'Eric:\nDi negeri ini, mengorbankan manusia dianggap membawa keberuntungan. Lagi pula, Pangeran Amor dan para pemuda gagah ini ada di sini.',
'2503':'Sophia:\nSekarang sedang musim pengorbanan bangsa Orc!',
'2504':'Prajurit Orc:\nLoktar! Aku mau manusia yang masih hidup!',
'3001':'Eric:\nItu Pangeran Amor! Kita tak boleh membiarkan para orc menyiksanya!',
'3002':'Eric:\nHahaha, sanggupkah kau menerima tiga pukulan dariku?',
'3003':'Pria Berotot:\nKau menang! Kau pejuang yang gagah dan kuat. Suatu hari nanti aku akan menantangmu lagi!',
'3004':'Eric:\nBaik! Tapi ingat, aku Eric, prajurit terbaik Raja Michael.',
'3005':'Pangeran Amor:\nKalau kalian bukan pengecut, temui kami di kota. Jumlah pria berotot kami lebih banyak daripada otot kalian!',
'3006':'Raja Pria Berotot:\nBaiklah, aku Raja Para Pria Berotot. Aku akan menyuruh anak buahku membiarkan kalian pergi dengan aman.',
'3007':'Eric:\nTerima kasih banyak. Ayo pergi!',
'3101':'Eric:\nPangeran Amor, ini wilayah bangsa Elf. Kita bisa meminta bantuan para elf untuk melawan Taimok!',
'3102':'Pangeran Amor:\nJangan lupa, kita punya musuh lain, Morrey. Dialah yang membunuh ayahku dan ingin menjadi raja!',
'3103':'Eric:\nKebenaran akan terungkap setelah kita kembali ke kota. Raja Elf Vironis adalah sekutu dan sahabat Raja Michael, jadi ia pasti membantu kita.',
'3104':'Pemanah Elf:\nPencuri lancang! Berani sekali kau menerobos gunung!',
'3401':'Eric:\nPenjaga semakin banyak. Kurasa Viron sudah dekat.',
'3402':'Sophia:\nBenar. Kita harus melindungi Pangeran Amor dan jangan sampai terpisah lagi.',
'3901':'Viron:\nBerhenti, orang asing! Aku Viron, Raja Elf. Mengapa kau melukai para penjagaku?',
'3902':'Eric:\nYang Mulia, aku Eric, sahabat tepercaya Raja Michael. Ini Pangeran Amor.',
'3903':'Eric meminta agar pasukan dikerahkan.',
'3904':'Viron:\nAku lelah dan tak berdaya. Banyak rakyat Elf menghilang belakangan ini.',
'3905':'Viron:\nKurasa kami harus pergi dari sini dan pindah ke tempat yang lebih aman.',
'3906':'Pangeran Amor:\nJika kami membantu mengatasi masalah ini, maukah kau membalas bantuan kami?',
'3907':'Viron:\nKami selalu menolong mereka yang membantu bangsa Elf. Kau dapat mengandalkan pasukanku.',
'3908':'Pangeran Amor:\nBaik! Eric akan membantumu menyelesaikan masalah ini. Tepati janjimu!',
'3909':'Eric:\nBaiklah!',
'4001':'Daisy:\nMulut yang menjijikkan!',
'4002':'Sophia:\nPangeran Amor berjanji kita akan membantu mengalahkan monster, tetapi sepertinya kita justru akan menjadi makanan mereka!',
'4003':'Eric:\nMinggir, biar aku yang menangani ini!',
'4004':'Viron:\nTerima kasih, para pejuang pemberani! Kami akan mengirim pasukan setelah beristirahat.',
'4005':'Eric:\nTerima kasih banyak! Namun kami harus pergi ke kota untuk menemui Jenderal Bushy. Aku akan menjelaskan kebenarannya dan meminta bantuannya.',
'4006':'Viron:\nHati-hati, di depan ada Puncak Kembar Api dan Es. Dua naga tinggal di sana: Mol si Naga Es yang telah tidur selama bertahun-tahun, dan Smokey si Naga Api yang menguasai gunung dengan amarahnya.',
'4007':'Viron:\nJika kau mengganggu Smokey yang pemarah, ia akan dengan senang hati membakarmu hingga menjadi abu!',
'4008':'Sophia:\nTerima kasih atas peringatannya! Aku akan merapal mantra tak terlihat agar mereka tidak menemukan kalian.',
'4101':'Pangeran Amor:\nItu gunung bersalju! Aku ingin melihat naga raksasa sungguhan!',
'4102':'Eric:\nPangeran, katanya naga es sedang tidur, tetapi naga api menguasai daerah itu.',
'4103':'Pangeran Amor:\nJadi aku hanya bisa melihat naga api? Sophia, bisakah kau membawaku menemuinya?',
'4104':'Sophia:\nTentu, Tuanku. Namun kita harus sangat tenang, kalau tidak mantranya akan gagal.',
'4105':'Sophia:\nBaiklah, baiklah. Ayo pergi!',
'4301':'Pangeran Amor:\nJembatannya rusak! Sophia, panggil jembatan ajaib!',
'4302':'Sophia:\nPangeran Amor, jarak ke seberang terlalu jauh. Sihirku tidak cukup kuat.',
'4303':'Eric:\nKita tak bisa menyeberangi sungai. Ayo ke selatan, mungkin ada jalan memutar.',
'4304':'Pangeran Amor:\nLebih baik kita mencari jalan keluar! Aku ingin melihat naga api!',
'4601':'Eric:\nAduh, tangga depan rusak. Sophia, cobalah memperbaikinya. Nanti pasti lebih baik.',
'4602':'Pangeran Amor:\nAku tak mau pergi ke seberang! Gunung berapi ada di selatan. Aku ingin melihat naga api!',
'4603':'Pangeran Amor:\nAyo ke selatan, Sophia. Aku ingin melihat naga api!',
'4604':'Sophia:\n...baiklah.',
'4901':'Sophia:\nPangeran Amor, ini jarak terdekat yang bisa kita capai. Jika kita terus bergerak, Ethan Drake akan menyadari sihirku.',
'4902':'Pangeran Amor:\nAyo, sedikit lagi.',
'4903':'Pangeran Amor:\nNah!',
'4904':'Ethan Drake:\nManusia! Pergi! Nagaku bisa mencium bau kalian!',
'5001':'Eric:\nCepat! Kita harus bergegas!',
'5002':'Sophia:\nLari sedikit lagi, aku akan memakai mantra untuk menyembunyikan kita! Cepat!',
'5101':'Penjaga:\nHei! Itu Eric si pengkhianat! Tangkap dia!',
'5102':'Eric:\nSiapa yang menyebutku pengkhianat? Aku sedang mengawal Pangeran Amor sendiri. Kami akan menemui Jenderal Bushy!',
'5103':'Penjaga:\nItu benar Pangeran Amor! Namun kau pengkhianat penjaga dan akan ditangkap untuk diadili. Hanya Pangeran Amor yang boleh menemui jenderal!',
'5104':'Pangeran Amor:\nKalian tunggu di sini. Aku akan ikut mereka, lalu menghukum Jenderal Bushy yang menjijikkan itu!',
'5105':'Eric:\nBaik, Tuanku.',
'5106':'Satu jam kemudian...',
'5107':'Eric:\nDi mana Pangeran Amor? Mengapa ia belum kembali?',
'5108':'Sophia:\nAyo masuk!',
'5109':'Daisy:\nBaik!',
'6001':'Eric:\nJenderal Bushy, akhirnya kita bertemu. Di mana Pangeran Amor?',
'6002':'Eric:\nApakah dia diberi obat? Mengapa tampangnya aneh sekali?',
'6003':'Pangeran Amor:\nEric! Akhirnya kau datang! Semua orang telah bersumpah setia kepada Sir Morrey dan ingin membawaku kembali ke kota!',
'6004':'Eric:\nPangeran Amor, senang bertemu lagi! Tujuan kita berikutnya adalah kota. Waktunya membalas dendam!',
'6005':'Pangeran Amor:\nSemoga perjalanan sejauh ini tidak berakhir dengan kematian kita di sini!',
'6101':'Eric:\nYang Mulia Viron, pasukanmu tampak besar dan kuat!',
'6102':'Viron:\nKami menepati janji! Semua penjaga kini berada di bawah mantra Taimok, tetapi sihirnya tak berpengaruh pada elf. Mari kita hadapi dia.',
'6103':'Viron:\nLindungi Pangeran Amor dengan baik.',
'6104':'Eric:\nBaik! Terima kasih banyak!',
'6105':'Kepala Pria Berotot:\nEric! Ayo bertarung lagi!',
'6106':'Eric:\nKepala Pria Berotot? Aku akan melawanmu setelah mengalahkan Taimok dan membawa Pangeran Amor ke kota.',
'6107':'Kepala Pria Berotot:\nTaimok? Lawan yang langka!',
'6108':'Kepala Pria Berotot:\nAku akan membantumu mengalahkan Taimok terlebih dahulu, lalu kita bertarung!',
'6109':'Pangeran Amor:\nUh... jangan sampai Taimok membunuhmu sebelum itu!',
'6501':'Eric:\nTaimok, ajalmu tiba! Katakan, di mana anak itu?',
'6502':'Pangeran Amor:\n...Kau membicarakanku?',
'6503':'Phoenix:\nManusia bodoh! Aku menyamar menjadi Pangeran Amor dan telah menipu kalian begitu lama, tetapi kalian terlalu bodoh untuk menyadarinya! Hahaha!',
'6504':'Phoenix:\nAku mengumpulkan kalian semua agar bisa menjadikan kalian anak buahku!',
'6505':'Phoenix:\nSepertinya aku tak bisa mengendalikan pikiran para elf. Tak masalah. Kau petarung berbakat; aku ingin bermain-main denganmu sedikit lebih lama.',
'6506':'Phoenix:\nTerus maju! Kepala Pria Berotot, habisi para elf yang tersisa!',
'7001':'Eric:\nSir Morrey! Kau pengkhianat! Kau ingin merebut takhta Raja Michael dan bersekongkol dengan Taimok Wong! Aku menjatuhkan hukuman mati kepadamu!',
'7002':'???:\nHahaha, kalian payah sekali!',
'7003':'Viron:\nKami menemukan Pangeran Amor yang asli dan Guru Kun! Pangeran Amor telah meminum racun, tetapi Guru Kun menggunakan sihir untuk menyelamatkan nyawanya.',
'7004':'Guru Kun:\nEric! Kau mengalahkan Taimok. Namamu akan segera terkenal!',
'7005':'Pangeran Amor:\nEric! Jangan bersedih! Kau menyelamatkan nyawaku, jadi aku akan mengangkatmu ke pangkat tertinggi Pengawal Raja. Bagaimana?',
'7006':'Eric:\nTerima kasih, Pangeran Amor! Walau aku berada di puncak hidup dan dikelilingi wanita cantik, aku tetap sedih setiap mengingat sekutu yang dibunuh Taimok.',
'7007':'Eric:\nIzinkan aku pergi dari sini dan kembali ke gunung raksasa!',
'7008':'Pangeran Amor:\nEric... kau? Tidak... kurasa racunnya mulai bekerja. Kepalaku pusing dan tubuhku sakit.',
'7009':'Daisy:\nGempa bumi! Lari!',
'7010':'Eric:\nDaisy! Hati-hati!',
'7011':'Daisy:\nAda sesuatu yang jahat berdiri di belakang Sir Morrey!',
'7012':'Eric:\nPengecut! Bersembunyi dalam bayangan, ya? Keluar dan lawan kami seperti lelaki sejati!',
'7013':'Sophia:\nEric, tenanglah.',
'7101':'Eric:\nKita di mana? Aku tak bisa melihat apa-apa.',
'7102':'Eric membangunkan semua orang...',
'7103':'Sophia:\nAku baik-baik saja! Kita di mana? Kota Kanberland ada... di atas kepala kita?',
'7104':'Eric:\nSepertinya ini sistem gua. Kita tak bisa memanjat keluar, jadi kita harus masuk lebih dalam dan mencari jalan keluar...',
'7201':'Guru Kun:\nAkhirnya kutemukan kalian. Syukurlah kalian selamat! Bagaimana dengan yang lain?',
'7202':'Eric:\nKami belum melihat mereka. Kami bertarung melawan iblis sepanjang jalan sampai ke sini. Sepertinya mereka tak ada habisnya!',
'7203':'Guru Kun:\nBegitu banyak iblis tepat di bawah kerajaan kita! Kita pasti masuk ke tengah rencana jahat mereka. Naskah kuno menceritakan gua bawah tanah luas yang menjadi tempat Makam Para Titan. Mungkinkah tempat ini gua itu?',
'7204':'Guru Kun:\nPara pahlawan pemberani, aku harus memastikan kerajaan tetap aman. Kejahatan sedang bergerak! Lanjutkan perjalanan dan cari sumber kehadiran iblis ini.',
'7205':'Eric:\nBaik, Guru Kun. Tolong jaga semua orang yang masih berada di permukaan. Lindungi Pangeran dengan segala cara!',
'7206':'Sophia:\nSepertinya kau tak akan kembali ke gunung dalam waktu dekat.',
'7207':'Eric:\nSepertinya begitu.',
'7401':'Gladiator Taimok:\nKALIAN SEMUA! BERANI-BERANINYA MENGGANGGU KAMI?!',
'7402':'Sophia:\nKatanya “mengganggu”? Sepertinya mereka sedang melakukan semacam ritual iblis!',
'7403':'Daisy:\nDia menghalangi pintu masuk jalur gunung. Sepertinya kita harus melewati penjilat ini dengan bertarung...',
'7701':'Succubus:\nTerlambat! Jantung Para Titan menjadi milik kami! Hahaha!',
'7702':'Sophia:\nJantung Para Titan? Menurut legenda, sebelum bangsa Titan punah, mereka menuangkan seluruh kekuatan ke satu artefak: Jantung itu. Siapa pun yang memilikinya dapat mengubah seluruh permukaan dunia!',
'7703':'Daisy:\nArtefak sekuat itu! Bagaimana mungkin kita bisa merebutnya?',
'7704':'Eric:\nMinggir, biar aku yang melakukannya!',
'8001':'Thousand Eyes:\nSampah manusia macam apa yang berani masuk ke sini? Penjaga! Bersihkan sampah manusia ini!',
'8002':'Sophia:\nPara penjagamu tak mampu menandingi kami! Kini tinggal kau dan kami. Serahkan Jantung Para Titan, maka kami akan memberimu kematian yang penuh belas kasihan.',
'8003':'Thousand Eyes:\nBegitu rupanya. Sepasang “pahlawan” lusuh dari kastil. Seharusnya kalian telah binasa bersama yang lain, tetapi tak masalah... kemarilah, bersenang-senanglah dengan Thousand Eyes!',
'8004':'Eric:\nJadi kaulah pelakunya! Bersiaplah menerima pembalasanku.',
'8005':'Sophia:\nTidak! Semua usaha kita sia-sia. Sepertinya dia bahkan tidak membawa Jantung Para Titan!',
'8006':'Eric:\nSetidaknya kita telah menegakkan keadilan atas serangan pengecut terhadap kerajaan kita!',
'8007':'Daisy:\nKita sudah berjalan sejauh ini. Apa kau yakin ingin kembali?',
'8008':'Sophia:\nAku sedang berpikir... Kita harus maju dan memeriksa Jantung Para Titan. Aku merasakan kekuatan besar dan kejahatan yang belum pernah ada dari arah Makam Para Titan.',
'8009':'Eric:\nItu sudah jelas, bukan? Lihat saja yang ada di belakangmu!',
'8010':'Sophia:\nLari! Jika kita bisa mengendalikan kekuatan Jantung Para Titan, mungkin kita bisa mengusir mereka!',
'99990':'Lihat! Aku bisa menyembuhkan hero yang terluka. Gambarlah garis dari aku menuju sasaran.',
'99991':'Lihat! Aku terluka! Gambarlah garis menuju diriku.',
'999901':'Marcus:\nPenggunaan mantra yang tepat sangat penting dalam pertarungan!',
'999902':'Marcus:\nPilih hero untuk melepaskan mantra, lalu ketuk aku.',
'999903':'Marcus:\nBagus! Mantraku ditampilkan di sudut kiri atas.',
'999904':'Marcus:\nKetuk ikon ini untuk menggunakan mantraku.',
'999905':'Marcus:\nMantra ini aktif saat berada dekat sasaran. Ketuk aku dan seret penunjuk ke sasaran untuk menyerang.',
'999906':'Marcus:\nSetiap hero memiliki waktu penggunaan mantra berbeda. Kamu harus menunggu sebelum menggunakannya lagi.',
'999907':'Marcus:\nTerus berlatih. Ketuk aku dan seret ke sasaran untuk menyerang.',
'999908':'Marcus:\nKetuk ikon mantra untuk menggunakannya. Karena aku dekat dengan sasaran, mantra akan langsung aktif.',
'999909':'Baldar:\nBagus! Sekarang lanjutkan latihan, ketuk aku.',
'999910':'Baldar:\nKetuk ikon mantra untuk menggunakannya. Mantra ini langsung aktif ketika aku menyerang.',
'999911':'Baldar:\nMantra ini aktif begitu kamu memberiku sasaran.',
'999912':'Baldar:\nSkill lain aktif seketika, seperti “Angin Puyuh”.',
'999913':'Baldar:\nHebat! Dalam pertarungan berikutnya, gunakan mantra dengan lebih efektif untuk meraih kemenangan!',
'999920':'Eric:\nPrajurit dapat memancing musuh agar menyerangnya.',
'999921':'Eric:\nSaat rekan tim yang lebih rentan berada dalam bahaya, serang musuh untuk menarik perhatiannya dan melindungi rekanmu.',
'999922':'Aeron:\nSetiap hero memiliki kemampuan berbeda untuk menarik perhatian musuh. Kuasai kemampuan ini untuk melindungi rekan tim.',
'999923':'Janus:\nSaat dalam bahaya, melindungi diri berarti menjaga jarak aman dari musuh!',
'999924':'Janus:\nBeberapa mantra memperlambat musuh sehingga kamu lebih aman.',
'999925':'Janus:\nBagus! Sekarang kalahkan semua musuh dan raih kemenangan!',
'0103':'Eric:\nAwas, ada gagak di depan! Sebaiknya aku mengalahkannya.',
'0104':'Eric:\nAku harus menggunakan skill “Pukulan Keras”. Ketuk untuk memilihku.',
'0105':'Eric:\nKetuk skill itu untuk menggunakannya dan mengalahkan gagak!',
'0106':'Sophia:\nBagus sekali, Eric! Ayo lanjutkan perjalanan kita.',
'8101':'Eric:\nAkhirnya kita berhasil mengusir para pengejar. Kita harus mendapatkan Jantung Titan dan menghindari masalah.',
'8102':'Sophia:\nTunggu! Aku mencium bau darah dari kejauhan. Tempat itu tampak berbahaya. Kita harus berhati-hati...',
'8103':'Daisy:\nAstaga! Jangan berkata begitu.',
'8401':'Centaur:\nWah, ternyata mendapatkan Jantung Titan sangat mudah.',
'8402':'Elf Kegelapan:\nSetelah bertahun-tahun berjuang, akhirnya kami melihat cahaya matahari!',
'8403':'Elf Kegelapan:\nBuat Viron dan para elf membayar semua ini!',
'8404':'Centaur:\nSetelah menyerap Jantung Titan, klan Elf Kegelapan akan menjadi yang terkuat di dunia.',
'9001':'Eric:\nApa? Elf?',
'9002':'Sophia:\nMereka Elf Kegelapan, kaum buangan yang diusir bangsa elf.',
'9003':'Centaur:\nDi dasar bumi, makam berlumuran darah merah. Di tengahnya terdapat Jantung Titan, sumber kekuatan tanpa akhir. Jangan takut. Biarkan bisikan jahat menuntun jalan kita!',
'9004':'Daisy:\nAstaga! Dia menyatu dengan Jantung Titan!',
'9005':'Centaur:\nAku akan membunuh kalian semua!!!',
'9006':'Eric:\nApa-apaan ini? Apa yang terjadi?!',
'9051':'Eric:\nJantung Titan telah mekar!',
'9052':'Sophia:\nKurasa itu hanya tiruan. Elf Kegelapan pasti dimanfaatkan oleh kejahatan!',
'9053':'Daisy:\nAstaga! Dasar makhluk jahat!',
'9054':'Eric:\nAyo lanjutkan. Kita akan segera mengetahui kebenarannya.'
}

ACHIEVEMENT_NAMES = [
'Darah Pertama','Pembasmi Monster','Perang Suci','Kok Bisa?','Sekarang Tidak Tangguh Lagi','Pemburu Penyihir','Pemusnahan!','Pengusir Roh','Sang Santo George','Tumbangkan Kaum Borjuis','Juara Lothian','Badai Gurun','Penakluk Amesbury','Jantung Hutan','Raja Perbukitan','Wali Kota Astolat','Penyelamat Umat Manusia','Tukang Kebun','Orang Terakhir Bertahan','Obat Itu untuk yang Lemah','Skuad Elit','Pertempuran Dua Pejuang','Jika Gagal, Coba Lagi...','Tidurlah dalam Api','Kematian Bukan Akhir','Santapan Naga','Penuh Uang','Bergelimang Harta','Kaya Raya','Ahli Perhiasan','Bertabur Permata','Dicetak dari Emas','Pemboros Besar','Semua yang Berkilau','Jackpot!','Menang Besar','Berani Bangkrut','Penjudi Besar','Pilih-Pilih','Bijaksana','Selektif','Persediaan Lengkap','Pemula','Veteran','Juara','Pahlawan','Kepala Berguling','Tak Tertembus','Aku Legenda','Tak Tertandingi','Pandai Besi','Pengrajin Ahli','Pengrajin Agung','Tak Terhentikan','Laksana Dewa','Terampil','Elit','Mahir','Kesempurnaan Tertinggi','Paling Dicari'
]
ACHIEVEMENT_DESC = [
'Kalahkan musuh pertamamu.','Kalahkan %D musuh.','Kalahkan %D musuh.','Kalahkan %D hewan.','Kalahkan %D petarung iblis.','Kalahkan %D pengguna sihir.','Kalahkan %D orc dari jenis apa pun.','Kalahkan %D musuh iblis.','Kalahkan naga Incendrak sebanyak %D kali.','Kalahkan perwira orc Tyler muda sebanyak %d kali.','Selesaikan Lothian.','Selesaikan Tanah Tandus.','Selesaikan Dataran Amesbury.','Selesaikan Hutan Gelap Linnuis.','Selesaikan Puncak Kembar Api dan Es.','Selesaikan Astolat.','Selesaikan Camelot.','Basmi semua Venus Deathtrap di tahap 4-5 sebanyak %D kali.','Menang dengan hanya satu penyintas.','Raih %D kemenangan tanpa bantuan penyembuh.','Raih %D kemenangan dengan 4 hero level 70 atau lebih tinggi.','Gunakan hanya dua hero untuk mengalahkan Phenex dan Maurax.','Kalah sebanyak %D kali.','Hero gugur di desa terbakar (tahap 1-6 atau 1-9).','Hidupkan kembali sekutu sebanyak %D kali.','Hero dimakan Ascalon sebanyak %D kali.','Dapatkan %D Koin emas.','Dapatkan %D Koin emas.','Dapatkan %D Koin emas.','Kumpulkan %D Kristal.','Kumpulkan %D Kristal.','Gunakan %D Kristal.','Belanjakan %D Koin emas.','Gunakan %D Kristal.','Dapatkan hadiah dari Roda Keberuntungan sebanyak %d kali.','Dapatkan telur kristal dari Roda Keberuntungan sebanyak %d kali.','Dapatkan %D Koin Goblin.','Putar roda sebanyak %D kali.','Segarkan daftar perlengkapan secara gratis sebanyak %D kali.','Gunakan emas untuk menyegarkan toko perlengkapan sebanyak %D kali.','Segarkan toko dengan koin sebanyak %d kali secara total.','Buka semua perlengkapan.','Buka semua bakat di halaman pertama seorang hero.','Buka semua bakat di halaman kedua seorang hero.','Buka semua bakat di halaman ketiga seorang hero.','Buka semua bakat di halaman keempat seorang hero.','Miliki senjata legendaris (perlengkapan jingga).','Kenakan pelindung dada legendaris (jingga).','Kenakan perlengkapan epik legendaris (merah).','Kenakan delapan perlengkapan epik (merah).','Tingkatkan perlengkapan sebanyak %D kali.','Tingkatkan perlengkapan sebanyak %D kali.','Tingkatkan perlengkapan sebanyak %D kali.','Tingkatkan perlengkapan epik ke level maksimum.','Tingkatkan perlengkapan legendaris ke level maksimum.','Dapatkan peringkat S di %d tahap.','Dapatkan peringkat S di %d tahap.','Dapatkan peringkat S di %d tahap.','Dapatkan peringkat S di %d tahap.','Kalahkan pencuri goblin sebanyak %d kali.'
]

NOTICES_DESC = [
'Pembelian Koin berhasil. Kamu sekarang memiliki tambahan %d Koin!',
'Pembelian Kristal berhasil. Kamu sekarang memiliki tambahan %d Kristal!',
'Bonus pembelian pertama! Kamu menerima %s x %d!',
'Peringkatmu di Tantangan Bos adalah %d. Klaim hadiahmu: %s x %d!',
'Kamu membelanjakan %s%d. Selamat, kamu menerima tambahan %s x %d!',
'Kamu membayar %s dalam satu pembelian. Ini hadiah untukmu: %s x %d.',
'Pada %s, peringkatmu adalah %d dan kamu menerima bonus %s x %d.'
]
STORE_DESC = [
'Merapatlah! Ada banyak barang langka dan menakjubkan di dalam!',
'Para ahli, berusahalah untuk mendapatkan poin.',
'Ketuk untuk melihat informasi barang; ambil langsung jika tertarik!',
'Jangan sungkan melihat-lihat.',
'Pilihanmu menentukan nasibmu. Jangan lewatkan kesempatan ini.',
'Persediaanku selalu berubah, pastikan untuk datang kembali!',
'Kamu mau membeli atau tidak?! Jadi, beli saja!',
'Waktu adalah uang, temanku.',
'Tepat sekali! Inilah perlengkapan terbaik.',
'Perlengkapan ini sangat sulit didapat; sebenarnya aku enggan menjualnya.',
'Acara ini berakhir pada 1 Desember.',
'Jika kau menemukan mataku, aku akan menukarkannya dengan barang legendaris.',
'Apakah kau sudah menemukan mataku?'
]
CARD_NAMES = ['Duri Es','Sulur','Ledakan','Penggal Kepala','Kebangkitan','Pelapukan','Penembak Jitu','Cyclops','Keheningan','Pengunyah','Perisai Angin','Magnetisme','Peri','Cahaya Totem','Para Juara','Totem Amarah','Larang Kartu Lawan','Dapatkan Kartu','Tipu Daya','Curi Kartu']

# Glossary used for item names only. Proper names and identifiers are intentionally retained.
GEAR_WORDS = {
'rusted':'berkarat','broadsword':'pedang lebar','fullered':'beralur','falchion':'pedang falchion','fine':'berkualitas','steel':'baja','sword':'pedang','shield':'perisai','sheild':'perisai','sword and shield':'pedang dan perisai','forged':'tempa','armaments':'persenjataan','arms':'senjata','armour':'zirah','armor':'zirah','blade':'bilah','dagger':'belati','dirk':'belati','knife':'pisau','knives':'pisau','cleaver':'golok','axe':'kapak','halberd':'halberd','polearm':'senjata galah','bow':'busur','longbow':'busur panjang','recurve':'busur lengkung','blunderbuss':'senapan gentel','gun':'senapan','staff':'tongkat sihir','stave':'tongkat sihir','rod':'tongkat','wand':'tongkat sihir','greatstaff':'tongkat sihir agung','sceptre':'tongkat kerajaan','crosier':'tongkat uskup','orb':'bola sihir','necklace':'kalung','neckchain':'rantai leher','ring':'cincin','pendant':'liontin','talisman':'jimat','prayerbeads':'tasbih','demonbeads':'manik iblis','belt':'sabuk','girdle':'ikat pinggang','waistguard':'pelindung pinggang','cloak':'jubah','cape':'mantel','mantle':'mantel','robe':'jubah','gown':'gaun','drapes':'jubah kain','cloth':'kain','leather':'kulit','hide':'kulit','bearskin':'kulit beruang','boots':'sepatu bot','shoes':'sepatu','greaves':'pelindung tulang kering','cowl':'penutup kepala','hood':'tudung','helm':'helm','helmet':'helm','barbute':'helm barbuta','skullcap':'kopiah baja','hat':'topi','mask':'topeng','circlet':'mahkota lingkar','breastplate':'pelindung dada','chestguard':'pelindung dada','cuirass':'zirah dada','platemail':'zirah pelat','plated':'berlapis zirah','pauldrons':'pelindung bahu','vest':'rompi','gilded':'bersepuh emas','golden':'emas','silver':'perak','copper':'tembaga','iron':'besi','titanium':'titanium','mithril':'mithril','wooden':'kayu','oaken':'kayu ek','reinforced':'diperkuat','toughened':'diperkeras','master-crafted':'buatan master','enchanted':'terpesona','magical':'ajaib','ethereal':'eteris','mysterious':'misterius','ancient':'kuno','divine':'ilahi','holy':'suci','blessed':'terberkati','cursed':'terkutuk','demonic':'iblis','dark':'gelap','light':'cahaya','fire':'api','ice':'es','storm':'badai','chaos':'kekacauan','royal':'kerajaan','nobleman\'s':'bangsawan','knight\'s':'kesatria','warrior\'s':'prajurit','guard\'s':'penjaga','minister\'s':'menteri','sorcerer\'s':'penyihir','hero\'s':'hero','elven':'elf','celestial':'surgawi','elemental':'elemental','guardian':'pelindung','high':'agung','great':'agung','half':'setengah','winged':'bersayap','horned':'bertanduk','red':'merah','green':'hijau','blue':'biru','white':'putih','black':'hitam','orange':'jingga','ruby':'rubi','jade':'giok','nephrite':'nefrit','iolite':'iolite','bloodstone':'batu darah','plume':'bulu','bear':'beruang','eye':'mata','eyes':'mata','heart':'jantung','soul':'jiwa','psychic':'psikis','insight':'wawasan','tenacity':'keteguhan','celerity':'kelincahan','purity':'kemurnian','keen':'tajam','guard':'penjaga','nightfall':'senja malam','night':'malam','eve':'malam perayaan','jester':'badut','viking':'Viking','standard':'standar','universal':'universal','possessed':'kerasukan','unyeilding':'tak tergoyahkan','spiritmail':'zirah roh','swathe':'balutan','coil':'lilitan','hand':'tangan','holly':'holi','stone':'batu','antiquity':'barang antik','bringer':'pembawa','battle':'pertempuran','power':'kekuatan','force':'daya','fortune':'keberuntungan','luck':'keberuntungan','fury':'kemarahan','rage':'amarah','blood':'darah','death':'kematian','dawn':'fajar','dusk':'senja','sun':'matahari','moon':'bulan','star':'bintang','stars':'bintang','dragon':'naga','demon':'iblis','titan':'Titan','elders':'tetua','court':'istana','prince':'pangeran','king':'raja','queen':'ratu','maiden':'gadis','guardian':'pelindung','protector':'pelindung','breaker':'penghancur','slayer':'pembasmi','bane':'kutukan','bane of':'pembasmi','reaper':'penuai','seeker':'pencari','bringer':'pembawa','master':'master','mighty':'perkasa','flame':'nyala api','frost':'beku','frozen':'membeku','crystal':'kristal','crystals':'kristal','gold':'emas','goblin':'goblin','yeti':'yeti','ancient':'kuno','lost':'hilang','forgotten':'terlupakan','eternal':'abadi','eternity':'keabadian','survivor':'penyintas','hope':'harapan','venom':'racun','poison':'racun','poisoned':'beracun','swift':'cepat','swiftly':'dengan cepat','blunt':'tumpul','sharp':'tajam','heavy':'berat','lightweight':'ringan','heavyweight':'berat','crude':'kasar','primitive':'primitif','improved':'ditingkatkan','superior':'unggul','perfect':'sempurna','legendary':'legendaris','epic':'epik','rare':'langka','common':'umum','uncommon':'tidak umum','leather':'kulit','chain':'rantai','mail':'zirah rantai','scale':'sisik','scales':'sisik','plate':'pelat','plume':'bulu','mantle':'mantel','neck':'leher','necklace':'kalung','amulet':'jimat','amulets':'jimat','artifact':'artefak','artifact of':'artefak','band':'gelang','bracelet':'gelang','shoes':'sepatu','trousers':'celana','leggings':'pelindung kaki','pants':'celana','greaves':'pelindung tulang kering','gloves':'sarung tangan','gauntlets':'sarung tangan baja','gauntlet':'sarung tangan baja','bracer':'pelindung lengan','bracers':'pelindung lengan','armlet':'gelang lengan','armlets':'gelang lengan','pauldron':'pelindung bahu','pauldrons':'pelindung bahu','shoulder':'bahu','shoulders':'bahu','charm':'jimat','charms':'jimat','pendulum':'bandul','fetish':'jimat','totem':'totem','idol':'berhala','prayer':'doa','prayerbeads':'tasbih','mantis':'belalang sembah','claw':'cakar','claws':'cakar','fang':'taring','fangs':'taring','horn':'tanduk','horns':'tanduk','skull':'tengkorak','bone':'tulang','bones':'tulang','feather':'bulu','feathers':'bulu','wing':'sayap','wings':'sayap','tail':'ekor','scale':'sisik','hide':'kulit','pelt':'kulit','fur':'bulu','skin':'kulit','chainmail':'zirah rantai','coat':'mantel','jacket':'jaket','tunic':'tunik','shirt':'baju','dress':'gaun','robe':'jubah','sash':'selempang','scepter':'tongkat kerajaan','spear':'tombak','lance':'tombak','trident':'trisula','mace':'gada','hammer':'palu','maul':'gada besar','club':'pentungan','staff':'tongkat sihir','crossbow':'busur silang','arrow':'panah','arrows':'panah','quiver':'tabung panah','quilted':'berlapis','embroidered':'bersulam','embroidered':'bersulam','studded':'berpaku','studded leather':'kulit berpaku','tattered':'compang-camping','tattered':'compang-camping','worn':'usang','sturdy':'kokoh','stout':'tebal','defender':'pelindung','defense':'pertahanan','defensive':'pertahanan','attacker':'penyerang','attacking':'serangan','attack':'serangan','caster':'perapal','sorcery':'sihir','wizard':'penyihir','assassin':'pembunuh','rogue':'penjahat','ranger':'ranger','paladin':'paladin','priest':'imam','priestess':'imam wanita','archer':'pemanah','marksman':'penembak jitu','musketeer':'musketeer','alchemist':'alkemis','necromancer':'nekromancer','warlock':'penyihir gelap','druid':'druid','monk':'biksu','barbarian':'barbar','berserker':'berserker','mercenary':'tentara bayaran','soldier':'prajurit','commander':'komandan','captain':'kapten','general':'jenderal','officer':'perwira','squire':'ajudan kesatria','knight':'kesatria','dragonhide':'kulit naga','dragonscale':'sisik naga','dragonbone':'tulang naga','demonhide':'kulit iblis','demonbone':'tulang iblis','angelic':'malaikat','angel':'malaikat','celestial':'surgawi','astral':'astral','arcane':'gaib','mystic':'mistik','mystical':'mistis','occult':'gaib','shadow':'bayangan','shadows':'bayangan','sunrise':'matahari terbit','sunset':'matahari terbenam','stormy':'badai','storm':'badai','wind':'angin','water':'air','earth':'bumi','air':'udara','thunder':'guntur','lightning':'petir','lightening':'petir','flame':'api','infernal':'neraka','hellfire':'api neraka','underworld':'dunia bawah','abyss':'jurang','void':'kehampaan','starfall':'jatuhnya bintang','starfire':'api bintang','moonlight':'cahaya bulan','sunlight':'cahaya matahari','sunshine':'sinar matahari','shadowed':'berbayang','glimmering':'berkilau','shining':'bercahaya','glittering':'berkilauan','sparkling':'berkilau','dazzling':'menyilaukan','glistening':'berkilau','gilded':'bersepuh emas','polished':'dipoles','sharpened':'diasah','tempered':'ditempa','forged':'tempa','hammered':'ditempa palu','runed':'berukir rune','rune':'rune','runic':'rune','mark':'tanda','marked':'bertanda','scarlet':'merah kirmizi','crimson':'merah tua','azure':'biru langit','emerald':'zamrud','sapphire':'safir','amethyst':'ametis','topaz':'topas','diamond':'berlian','pearl':'mutiara','obsidian':'obsidian','onyx':'onyx','amethyst':'ametis','garnet':'batu garnet','peridot':'peridot','quartz':'kuarsa','obsidian':'obsidian','bloodstone':'batu darah','moonstone':'batu bulan','sunstone':'batu matahari','crystal':'kristal','crystalline':'kristalin','jade':'giok','nephrite':'nefrit','iolite':'iolite','ruby':'rubi','lapis':'lapis lazuli','amber':'ambar','opal':'opal','turquoise':'pirus','glass':'kaca','wood':'kayu','oak':'kayu ek','pine':'pinus','birch':'birch','ash':'abu','yew':'yew','bone':'tulang','ivory':'gading','bronze':'perunggu','brass':'kuningan','silver':'perak','gold':'emas','golden':'emas','copper':'tembaga','iron':'besi','steel':'baja','mithril':'mithril','adamantine':'adamantine','titanium':'titanium','obsidian':'obsidian','black':'hitam','white':'putih','red':'merah','green':'hijau','blue':'biru','purple':'ungu','violet':'ungu','orange':'jingga','yellow':'kuning','grey':'abu-abu','gray':'abu-abu','pink':'merah muda','brown':'cokelat','silvered':'berlapis perak','golden':'emas','royal':'kerajaan','imperial':'kekaisaran','noble':'bangsawan','nobleman':'bangsawan','pristine':'murni','radiant':'bercahaya','twilight':'senja','dawn':'fajar','dusk':'senja','midnight':'tengah malam','eternal':'abadi','everlasting':'abadi','endless':'tanpa akhir','infinite':'tak terhingga','immortal':'abadi','mortal':'fana','heroic':'heroik','hero':'hero','mythic':'mitis','mythical':'mitis','legend':'legenda','legendary':'legendaris','epic':'epik','rare':'langka','common':'umum','ancient':'kuno','antique':'antik','antiquity':'zaman kuno','primitive':'primitif','rusted':'berkarat','rusty':'berkarat','broken':'rusak','cracked':'retak','shattered':'hancur','reborn':'terlahir kembali','rebirth':'kelahiran kembali','relic':'relik','relics':'relik','treasure':'harta','treasured':'berharga','treasure of':'harta','kingdom':'kerajaan','camelot':'Camelot','avalon':'Avalon','excalibur':'Excalibur','sir':'Sir','sir erec':'Sir Erec','esclados':'Esclados','esclabor':'Esclabor','green knight':'Ksatria Hijau','ninianne':'Ninianne','lothian':'Lothian','amesbury':'Amesbury','astolat':'Astolat','titans':'Titan','titan':'Titan'
}
# Phrase-aware item-name translation. Translate object names first, then their descriptors,
# rather than mechanically substituting words in English order. Proper names remain intact.
GEAR_WORDS.update({
    'the':'', 'of':'', 'and':'dan', 'with':'dengan', 'for':'untuk', 'in':'di', 'on':'pada',
    'crook':'tongkat','persecutor':'penghukum','persector':'penghukum','executioner':'algojo',
    'great':'agung','brutal':'brutal','flawless':'sempurna','war':'perang','axe':'kapak','pike':'tombak',
    'talwar':'pedang talwar','harpe':'pedang harpe','stonecrusher':'Penghancur Batu','skullsmasher':'Pemecah Tengkorak',
    'soulreaper':'Penuai Jiwa','fleshripper':'Penyobek Daging','red mist':'Kabut Merah','ragnarok':'Ragnarok',
    'mercygiver':'Pemberi Belas Kasih','spiritedge':'Bilah Roh','soulmyst':'Misteri Jiwa','carnwennan':'Carnwennan',
    'silent ruin':'Kehancuran Senyap','oberson':'Oberon','oberon':'Oberon','vengance':'pembalasan','vengeance':'pembalasan',
    'harbinger':'pertanda','pestilence':'sampar','barb':'duri','crescent':'sabit','crescent sun':'matahari sabit',
    'incineration':'pembakaran','divination':'ramalan','bastion':'benteng','knowledge':'pengetahuan','dissolution':'pelarutan',
    'animosity':'permusuhan','delusion':'khayalan','malevolence':'niat jahat','proliferation':'perkembangbiakan',
    'martyr':'martir','reverance':'penghormatan','reverence':'penghormatan','transition':'peralihan','celestial':'surgawi',
    'emination':'pancaran','emanation':'pancaran','final':'terakhir','spiritual':'spiritual','illuminati':'Illuminati',
    'judiciary':'peradilan','persecutor':'penganiaya','absolution':'pengampunan','libertas':'kebebasan','crucifier':'penyalib',
    'tempest':'badai','moxie':'keberanian','conjuration':'pemanggilan','runestone':'batu rune','tomes':'kitab',
    'stormjewel':'Permata Badai','spectral':'gaib','invocation':'pemanggilan','hellawes':'Hellawes','fire':'api',
    'tao':'Tao','sunstaff':'tongkat matahari','taurus':'Taurus','standard':'panji','st george':'Santo George',
    'serpantstaff':'Tongkat Ular','rancor':'dendam','rock':'batu','marduk':'Marduk','amun ra':'Amun Ra',
    'ravenstave':'Tongkat Gagak','dissolution':'pelarutan','chaos':'kekacauan','mystic':'mistik','sapphire':'safir',
    'dragontooth':'gigi naga','unending':'tiada akhir','darkness':'kegelapan','dark elven':'elf kegelapan',
    'chief':'kepala suku','makya':'Makya','aconite':'aconite','armoured':'berzirah','sinewed':'berurat kayu',
    'ash':'kayu ash','dragonslayer':'pembunuh naga','keen':'tajam','valience':'keberanian','valiance':'keberanian',
    'ruination':'kehancuran','wrath':'murka','deathspitter':'Pelontar Maut','satan':'Satan','antiquated':'kuno',
    'flintlock':'sumbu batu','coach':'pelatih','cartridge':'kartrid','firing':'tembak','musket':'senapan musket',
    'enfield':'Enfield','nock':'Nock','musketoon':'senapan kecil','multiblaster':'Blaster Multitembak',
    'sharps':'Sharps','rifle':'senapan laras panjang','sighted':'berbidik','winchester':'Winchester','leadblazer':'Pembakar Timah',
    'brown bess':'Brown Bess','skyburner':'Pembakar Langit','ransacker':'Penjarah','thunderblaster':'Blaster Guntur',
    'collosoblaster':'Blaster Kolosal','horned':'bertanduk','crested':'berjambul','reinforced':'diperkuat',
    'knights':'kesatria','knight':'kesatria','sallet':'helm sallet','visor':'pelindung wajah','captains':'kapten',
    'champions':'para juara','uncle':'Paman','dap':'Dap','headband':'ikat kepala','mountain':'gunung','wolf':'serigala',
    'forest':'hutan','suede':'suede','stetson':'Stetson','chrome-tanned':'samakan krom','half face':'setengah wajah',
    'soldiers':'prajurit','tricorne':'topi tricorne','extravagant':'mewah','intimidation':'intimidasi','trepidation':'ketakutan',
    'patchwork':'tambal sulam','phrygian':'Frigia','orcskin':'kulit orc','satin':'satin','pointed':'runcing',
    'sorcerer':'penyihir','coronet':'mahkota kecil','third':'ketiga','mitre':'mitra','veneration':'pemujaan',
    'embroidered':'bersulam','headpiece':'hiasan kepala','elemental':'elemental','breastplate':'pelindung dada',
    'spauldrons':'pelindung bahu','spaulder':'pelindung bahu','bronze':'perunggu','bevor':'pelindung leher',
    'gladiator':'gladiator','greek':'Yunani','cuirass':'zirah dada','lightweight':'ringan','theseus':'Theseus',
    'spartaсus':'Spartacus','spartacus':'Spartacus','worn':'usang','shoulderpads':'pelindung bahu','torso':'tubuh',
    'officer':'perwira','resiliant':'tangguh','resilient':'tangguh','trellised':'berjaring','hauberk':'zirah rantai',
    'captain':'kapten','jerkin':'jaket kulit','imperishable':'tak lapuk','deathmonger':'pembawa maut','brigandine':'zirah brigandin',
    'unyeilding':'tak tergoyahkan','unyielding':'tak tergoyahkan','blessed':'terberkati','imperial':'kekaisaran',
    'demon-hide':'kulit iblis','opulent':'mewah','ambar':'Ambar','commissioner':'komisaris','yeti':'Yeti',
    'nandi':'Nandi','hooded':'bertudung','gnostic':'gnostik','ucadia':'Ucadia','guilded':'bersepuh emas',
    'fortitude':'ketahanan','pasupati':'Pasupati','exquisite':'indah','luminance':'pancaran cahaya','link':'rantai',
    'demonic':'iblis','copper':'tembaga','plated':'berlapis','camelot forged':'tempa Camelot','greatness':'keagungan',
    'might':'kekuatan','old':'lama','riveted':'berpaku keling','orks':'orc','orks kin':'kulit orc','inner circle':'lingkaran dalam',
    'bracers':'pelindung lengan','spiritwalkers':'pejalan roh','high elven':'elf agung','demonhide':'kulit iblis',
    'earthen':'bumi','root':'akar','royal':'kerajaan','sash':'selempang','cincture':'ikat pinggang',
    'fortified':'diperkuat','celestial protection':'perlindungan surgawi','clogs':'sepatu kayu','spiked':'berpaku',
    'sabatons':'sepatu zirah','calfskin':'kulit anak sapi','open-toe':'ujung terbuka','lockseley':'Lockseley',
    'elders':'tetua',"nobleman's":'bangsawan','drapes':'kain jubah','nightfall':'senja malam','bearskin':'kulit beruang',
    'ethereal':'eteris','azure':'biru langit','bloodstone':'batu darah','nephrite':'nefrit','demonbeads':'manik iblis',
    'prayerbeads':'tasbih','psychic':'psikis','insight':'wawasan','plume':'bulu','jester':'badut',
    'sir erec':'Sir Erec','sir dinadan':'Sir Dinadan','sir balan':'Sir Balan','sir gawaine':'Sir Gawaine',
    'sir ector':'Sir Ector','sir lamorak':'Sir Lamorak','sir yvain':'Sir Yvain','sir tristan':'Sir Tristan','sir kay':'Sir Kay',
    'sir galahad':'Sir Galahad','sir lucan':'Sir Lucan','young tyler':'Tyler muda','morgan le fay':'Morgan Le Fay',
    'chief makya':'Kepala Suku Makya','the green knight':'Ksatria Hijau','the golden knight':'Ksatria Emas',
    'the red knight':'Ksatria Merah','the black knight':'Ksatria Hitam','mordred':'Mordred','esclados':'Esclados',
    'esclabor':'Esclabor','pridwen':'Pridwen','excalibur':'Excalibur','avalon':'Avalon','camelot':'Camelot',
    'asguard':'Asguard','asgard':'Asgard','archangel micheal':'Malaikat Agung Michael','uther pendragon':'Uther Pendragon',
    'st. george':'Santo George','st george':'Santo George','sir':'Sir','young':'muda','chief':'kepala suku'
})


# Extended terminology for the full 688-item catalogue. Named characters/franchises
# are retained; descriptive English terms are translated into natural Indonesian.
GEAR_WORDS.update({
    'alderwood':'kayu alder','vinewood':'kayu rambat','sapling':'bibit pohon','eternal':'abadi',
    'everlasting':'abadi','warped':'terdistorsi','martyr':'martir','judgement':'penghakiman',
    'judgment':'penghakiman','venerated':'yang dipuja','restorer':'pemulih','eartly':'bumi',
    'earthly':'bumi','righteous':'orang benar','emissary':'utusan','god':'Tuhan','swiftblade':'bilah cepat',
    'pride':'kebanggaan','blademaster':'ahli pedang','demonhunter':'pemburu iblis','twisted':'terpilin',
    'rain':'hujan','sinewed':'berurat','high lord':'penguasa tinggi','lord':'penguasa','guards':'pengawal',
    'guard':'pengawal','ancient':'kuno','royal':'kerajaan','knights':'kesatria','hardened':'diperkeras',
    'sallet':'helm sallet','suede':'suede','stetson':'Stetson','phrygian':'Frigia','elemental':'elemental',
    'champions':'juara','gladiator':'gladiator','cuirass':'zirah dada','warrior':'prajurit','torso':'tubuh',
    'trellised':'berjaring','captain':'kapten','fine':'berkualitas','jerkin':'jaket kulit','unyielding':'tak tergoyahkan',
    'garb':'busana','mystic':'mistik','warlock':'penyihir gelap','sorcerer':'penyihir','gilded':'bersepuh emas',
    'copper-gilded':'bersepuh tembaga','copper-riveted':'berpaku keling tembaga','orks kin':'kulit orc',
    'spiritwalkers':'pejalan roh','high elven':'elf tinggi','demonhide':'kulit iblis','nobleman':'bangsawan',
    'phoenix':'Phoenix','tailfeather':'bulu ekor','astral':'astral','revealer':'pewahyu','windrider':'Windrider',
    'enhanced':'ditingkatkan','sun-chaser':'pengejar matahari','consultant':'penasihat','christmas':'Natal',
    'wonderstaff':'tongkat ajaib','candy cane':'tongkat permen','red-nosed':'berhidung merah','antler':'tanduk',
    'ministers':'menteri','arch-angel':'malaikat agung','archangel':'malaikat agung','assassin':'pembunuh',
    'baby-dragon':'bayi naga','royal archer':'pemanah kerajaan','eagle':'elang','captain of the guard':'kapten pengawal',
    'royal court jester':'badut istana kerajaan','captain of the guard':'kapten pengawal','universal':'universal',
    'virgin mother':'Bunda Perawan','redemption':'penebusan','guardian':'pelindung','emissary':'utusan',
    'illuminati':'Illuminati','restorer of':'pemulih','steel rain':'hujan baja','micheal':'Michael',
    'earthly balance':'keseimbangan bumi','spiritual light':'cahaya spiritual','swift':'cepat','captains':'kapten',
    'knight':'kesatria','knight’s':'kesatria','sword':'pedang','swords':'pedang','armor':'zirah','armour':'zirah',
    'cloak':'jubah','necklace':'kalung','ring':'cincin','universal cloak':'jubah universal',
})

PHRASE_TRANSLATIONS = {
    'gem of martyr\'s blood':'Permata Darah Martir',
    'restorer of eartly balance':'Pemulih Keseimbangan Bumi',
    'restorer of earthly balance':'Pemulih Keseimbangan Bumi',
    'lance of divine judgement':'Tombak Penghakiman Ilahi',
    'lance of divine judgment':'Tombak Penghakiman Ilahi',
    'sceptre of the venerated':'Tongkat Kerajaan yang Dipuja',
    'scepter of the venerated':'Tongkat Kerajaan yang Dipuja',
    'guardian of the righteous':'Pelindung Orang Benar',
    'emissary of god':'Utusan Tuhan',
    'talisman of the virgin mother':'Jimat Bunda Perawan',
    'eternal sapling':'Bibit Pohon Abadi',
    'mysterious warped stave':'Tongkat Sihir Misterius yang Terdistorsi',
    'titanium swiftblade':'Bilah Cepat Titanium',
    'ancient royal guard':'Pengawal Kerajaan Kuno',
    'dark elven high lord':'Penguasa Tinggi Elf Gelap',
    'dark elven knight':'Kesatria Elf Gelap',
    'dark elven general':'Jenderal Elf Gelap',
    'dark elven':'Elf Gelap',
    'high elven':'Elf Tinggi',
    'royal guard':'Pengawal Kerajaan',
    'royal guards':'Pengawal Kerajaan',
    'gladiator champions':'Juara Gladiator',
    'titanium champions':'Juara Titanium',
    'captain of the guard':'Kapten Pengawal',
    'royal court jester':'Badut Istana Kerajaan',
    'arch-angel':'Malaikat Agung',
    'archangel':'Malaikat Agung',
    'demon hunter':'Pemburu Iblis',
    'royal archer':'Pemanah Kerajaan',
    'baby-dragon':'Bayi Naga',
    'sun-chaser':'Pengejar Matahari',
    'royal consultant':'Penasihat Kerajaan',
    'master-crafted':'buatan ahli',
    'master crafted':'buatan ahli',
    'camelot-forged':'tempa Camelot',
    'captain\'s':'kapten',
    'sir lucan':'Sir Lucan',
    'robin hood':'Robin Hood',
    'nobleman':'bangsawan',
    'nobleman\'s':'bangsawan',
}

OBJECTS = [
    ('sword and shield','Pedang dan perisai'),('longbow','Busur panjang'),('broadsword','Pedang lebar'),('falchion','Pedang falchion'),
    ('war cleaver','Golok perang'),('battle axe','Kapak perang'),('double-headed axe','Kapak bermata dua'),("executioner's halberd",'Halberd algojo'),
    ('skullcap','Kopiah baja'),('half face mask','Topeng setengah wajah'),('headband','Ikat kepala'),('pointed hat','Topi runcing'),
    ('breastplate','Pelindung dada'),('chestguard','Pelindung dada'),('chestplate','Pelat dada'),('waistguard','Pelindung pinggang'),
    ('steel dagger','Belati baja'),('longbow','Busur panjang'),('blunderbuss','Senapan gentel'),('coach gun','Senapan Coach'),
    ('cartridge-firing musket','Senapan musket peluru'),('cartrige musketoon','Senapan kecil peluru'),('musketoon','Senapan kecil'),
    ("sorcerer's pointed hat",'Topi runcing penyihir'),('elemental headpiece','Hiasan kepala elemental'),('gilded breastplate','Pelindung dada bersepuh emas'),
    ('satin pointed hat','Topi runcing satin'),('leather half face mask','Topeng setengah wajah dari kulit'),('spiritmail cloak','Jubah zirah roh'),
    ('toughened leather boots','Sepatu bot kulit yang diperkeras'),('clogs','Sepatu kayu'),('wooden clogs','Sepatu kayu'),
    ('copper plated girdle','Ikat pinggang berlapis tembaga'),('royal sash','Selempang kerajaan')
]

def translate_atom(token):
    raw=token
    key=token.lower()
    if key in GEAR_WORDS:
        return GEAR_WORDS[key]
    # Strip a possessive ending when it is not an explicit phrase in the glossary.
    key=key.replace('’',"'")
    if key.endswith("'s") and key[:-2] in GEAR_WORDS: return GEAR_WORDS[key[:-2]]
    # Unknown single words in item names can be named artefacts/characters; keep them instead of mangling.
    return raw

def translate_modifiers(text):
    # Protect recognized phrases so later word-by-word replacements do not scramble them.
    protected={}
    result=text
    for i,(phrase,translation) in enumerate(sorted(PHRASE_TRANSLATIONS.items(),key=lambda item:len(item[0]),reverse=True)):
        token=f'§PHRASE{i}§'
        pattern=r'(?<![A-Za-z])'+re.escape(phrase)+r'(?![A-Za-z])'
        if re.search(pattern,result,re.I):
            result=re.sub(pattern,token,result,flags=re.I)
            protected[token]=translation
    words=re.findall(r"[A-Za-z]+(?:['’-][A-Za-z]+)*|[^A-Za-z]+", result)
    result=''.join(translate_atom(w) if re.fullmatch(r"[A-Za-z]+(?:['’-][A-Za-z]+)*",w) else w for w in words).strip()
    for token,translation in protected.items(): result=result.replace(token,translation)
    return result


GEAR_EXACT = {
    "a wintry wonderstaff": "Tongkat Ajaib Musim Dingin",
    "gem of martyr's blood": "Permata Darah Martir",
    "eternal sapling": "Bibit Pohon Abadi",
    "mysterious warped stave": "Tongkat Sihir Misterius yang Terdistorsi",
    "lance of divine judgement": "Tombak Penghakiman Ilahi",
    "lance of divine judgment": "Tombak Penghakiman Ilahi",
    "sceptre of the venerated": "Tongkat Kerajaan yang Dipuja",
    "restorer of eartly balance": "Pemulih Keseimbangan Bumi",
    "restorer of earthly balance": "Pemulih Keseimbangan Bumi",
    "guardian of the righteous": "Pelindung Orang Benar",
    "emissary of god": "Utusan Tuhan",
    "rod of redemption": "Tongkat Penebusan",
    "talisman of the virgin mother": "Jimat Bunda Perawan",
    "titanium swiftblade": "Bilah Cepat Titanium",
    "master-crafted dagger": "Belati Buatan Ahli",
    "camelot-forged steel dagger": "Belati Baja Tempa Camelot",
    "curved elven dagger": "Belati Lengkung Elf",
    "blademaster's pride": "Kebanggaan Ahli Pedang",
    "ancient demonhunter's blade": "Bilah Pemburu Iblis Kuno",
    "twisted wooden staff": "Tongkat Sihir Kayu Terpilin",
    "heart of the stone titan": "Jantung Titan Batu",
    "yew longbow": "Busur Panjang Kayu Yew",
    "armoured bow of sinewed ash": "Busur Berzirah dari Kayu Ash Berurat",
    "master-crafted keen bow": "Busur Tajam Buatan Ahli",
    "steel rain": "Hujan Baja",
    "hero's longbow": "Busur Panjang Hero",
    "dark elven high lord's bow": "Busur Penguasa Tinggi Elf Gelap",
    "grand blunderbuss": "Senapan Gentel Agung",
    "steel knights' helm": "Helm Kesatria Baja",
    "hardened steel knight's helm": "Helm Kesatria Baja yang Diperkeras",
    "sir lucan's great helm": "Helm Agung Sir Lucan",
    "hardened steel sallet with visor": "Helm Sallet Baja Diperkeras dengan Pelindung Wajah",
    "suede stetson": "Topi Stetson dari Suede",
    "orcskin phrygian hat": "Topi Frigia Kulit Orc",
    "satin pointed hat": "Topi Runcing Satin",
    "sorcerer's pointed hat": "Topi Runcing Penyihir",
    "elemental headpiece of water": "Hiasan Kepala Elemental Air",
    "royal guards' breastplate": "Pelindung Dada Pengawal Kerajaan",
    "gladiator champions' breastplate": "Pelindung Dada Juara Gladiator",
    "titanium champions' breastplate": "Pelindung Dada Juara Titanium",
    "titanium chestguard with cuirass": "Pelindung Dada Titanium dengan Zirah Dada",
    "dark elven knight's chestguard": "Pelindung Dada Kesatria Elf Gelap",
    "dark elven general's chestguard": "Pelindung Dada Jenderal Elf Gelap",
    "hero's mithril chestguard": "Pelindung Dada Mithril Hero",
    "warrior's torso armour": "Zirah Tubuh Prajurit",
    "ranger's trellised hauberk": "Zirah Rantai Ranger Berjaring",
    "captain's jerkin with fine steel pauldrons": "Jaket Kulit Kapten dengan Pelindung Bahu Baja Berkualitas",
    "dark elven chestguard": "Pelindung Dada Elf Gelap",
    "hero's vest with unyeilding pauldrons": "Rompi Hero dengan Pelindung Bahu Tak Tergoyahkan",
    "hero's vest with unyielding pauldrons": "Rompi Hero dengan Pelindung Bahu Tak Tergoyahkan",
    "demon-hide and mithril chestguard": "Pelindung Dada Kulit Iblis dan Mithril",
    "shadow warrior's garb": "Busana Prajurit Bayangan",
    "mystic's robe": "Jubah Mistik",
    "warlock's robe": "Jubah Penyihir Gelap",
    "shadow sorcerer's gown": "Gaun Penyihir Bayangan",
    "sorcerer's garb": "Busana Penyihir",
    "mithril girdle": "Ikat Pinggang Mithril",
    "copper-gilded leather belt": "Sabuk Kulit Bersepuh Tembaga",
    "copper-riveted leather belt": "Sabuk Kulit dengan Paku Keling Tembaga",
    "titanium gilded orkskin belt": "Sabuk Kulit Orc Titanium Bersepuh Emas",
    "titanium bracers of the spiritwalkers": "Pelindung Lengan Titanium Pejalan Roh",
    "gilded elven belt": "Sabuk Elf Bersepuh Emas",
    "gilded high elven belt": "Sabuk Elf Tinggi Bersepuh Emas",
    "titanium gilded demonhide belt": "Sabuk Kulit Iblis Titanium Bersepuh Emas",
    "hero's greaves": "Pelindung Tulang Kering Hero",
    "nobleman's cowl": "Tudung Bangsawan",
    "warrior's blade": "Bilah Prajurit",
    "thorns staff": "Tongkat Duri",
    "longbow of robin hood": "Busur Panjang Robin Hood",
    "phoenix's tailfeather": "Bulu Ekor Phoenix",
    "astral revealer": "Pewahyu Astral",
    "windrider's enhanced bow": "Busur Windrider yang Ditingkatkan",
    "angel's mask": "Topeng Malaikat",
    "demon hunter's chestguard": "Pelindung Dada Pemburu Iblis",
    "leviathan skin belt": "Sabuk Kulit Leviathan",
    "sun-chaser's greaves": "Pelindung Tulang Kering Pengejar Matahari",
    "royal consultant's boots": "Sepatu Bot Penasihat Kerajaan",
    "solid christmas armed": "Perlengkapan Natal Kokoh",
    "winter wonderstaff": "Tongkat Ajaib Musim Dingin",
    "killer candy cane": "Tongkat Permen Pembunuh",
    "red-nosed antler bow": "Busur Tanduk Berhidung Merah",
    "captain of the guard's helm": "Helm Kapten Pengawal",
    "royal court jester's hat": "Topi Badut Istana Kerajaan",
    "ministers mithril chestguard": "Pelindung Dada Mithril Menteri",
    "orc-skin armor": "Zirah Kulit Orc",
    "arch-angel's holy staff": "Tongkat Suci Malaikat Agung",
    "high assassin's blade": "Bilah Pembunuh Ulung",
    "baby-dragon wing staff": "Tongkat Sayap Bayi Naga",
    "baby-dragon staff": "Tongkat Bayi Naga",
    "royal archer's bow": "Busur Pemanah Kerajaan",
    "captain's sword": "Pedang Kapten",
    "eagle's bow": "Busur Elang",
    "nobleman's leather": "Kulit Bangsawan",
}


GEAR_EXACT.update({
    'mithril plated dirk':'Belati Mithril Berlapis',
    'enchanted elven blade':'Bilah Elf Terpesona',
    'curved elven dagger':'Belati Lengkung Elf',
    'composite recurve bow':'Busur Lengkung Komposit',
    'compound recurve bow':'Busur Lengkung Majemuk',
    'bow of accuracy':'Busur Akurasi',
    'bow of the demonic aconite':'Busur Aconite Iblis',
    "dragonslayer's bow":"Busur Pembasmi Naga",
    'compound bow of vengeance':'Busur Majemuk Pembalasan',
    "teucer's bladed bow":"Busur Berbilah Teucer",
    'greatbow of ruination':'Busur Agung Kehancuran',
    "viking captains' barbute":"Helm Barbuta Kapten Viking",
    'chrome-tanned stetson':'Topi Stetson yang Disamak Krom',
    'elemental headpiece of earth':'Hiasan Kepala Elemental Bumi',
    "high commissioner's gown":"Gaun Komisaris Agung",
    'demonic aconite root':'Akar Aconite Iblis',
    'axe of wild elemental':'Kapak Elemental Liar',
    "moses' mask":"Topeng Musa",
    'orichalcum plate armor':'Zirah Pelat Orichalcum',
    'elemental magic robe':'Jubah Sihir Elemental',
    "heracles' waistguard":"Pelindung Pinggang Heracles",
    'ghostdom belt':'Sabuk Dunia Hantu',
    "berserker's ham":"Paha Babi Berserker",
    "rudolph's slay bells staff":"Tongkat Lonceng Pembantai Rudolph",
    'poison lollipop':'Lolipop Beracun',
    'prongs of pain':'Duri Penderitaan',
    'red rider bb gun':'Senapan BB Red Rider',
    'ceremonial court helmet':'Helm Upacara Istana',
    "minister's wartime cloak":"Jubah Perang Menteri",
    "minster's plated belt":"Sabuk Berlapis Minster",
    "minister's leather belt":"Sabuk Kulit Menteri",
    "minister's beltcloth":"Kain Sabuk Menteri",
    "minister's wartime greaves":"Pelindung Tulang Kering Perang Menteri",
    "minister's leather boots":"Sepatu Bot Kulit Menteri",
    "minister's boots":"Sepatu Bot Menteri",
    'glowing battle axe':'Kapak Perang Berkilau',
    'gift of the magi staff':'Tongkat Hadiah Orang Majus',
    "minister's dagger":"Belati Menteri",
    'hand cannon':'Meriam Genggam',
    'elemental gun':'Senapan Elemental',
    'universal cloak':'Jubah Universal',
    'universal necklace':'Kalung Universal',
    'universal ring':'Cincin Universal',
    'halloween sword and shield':'Pedang dan Perisai Halloween',
    'halloween pumpkin hammer':'Palu Labu Halloween',
    'halloween dagger':'Belati Halloween',
    'halloween staff':'Tongkat Sihir Halloween',
    'halloween bow':'Busur Halloween',
    'halloween umbrella gun':'Senapan Payung Halloween',
    'deva\'s staff':'Tongkat Sihir Deva',
    'illuminati staff':'Tongkat Sihir Illuminati',
    'hero\'s mithril chestguard':'Pelindung Dada Mithril Hero',
    'ranger\'s trellised hauberk':'Zirah Rantai Ranger Berjaring',
    'demon-hide and mithril chestguard':'Pelindung Dada Kulit Iblis dan Mithril',
    'ranger\'s belt':'Sabuk Ranger',
    'gilded high elven belt':'Sabuk Elf Tinggi Bersepuh Emas',
    'gilded elven belt':'Sabuk Elf Bersepuh Emas',
    'windrider\'s enhanced bow':'Busur Windrider yang Ditingkatkan',
    'universal ring':'Cincin Universal',
    'captain\'s sword':'Pedang Kapten',
    'thor\'s hammer':'Palu Thor',
    'grote\'s wand':'Tongkat Sihir Grote',
    'hulk\'s gloves':'Sarung Tangan Hulk',
    'loki\'s staves':'Tongkat Sihir Loki',
    'elemental gun':'Senapan Elemental',
    'iron suit':'Set Zirah Besi',
    'elemental pumpkin hammer':'Palu Labu Elemental',
})

def translate_gear_name(value):
    if not value: return value
    v=re.sub(r'\s+',' ',value).strip()
    low=v.lower().replace('’',"'")
    if low in GEAR_EXACT: return GEAR_EXACT[low]
    # Exact narrative weapon phrases and named armaments.
    special={
        "the green knight's armaments":"Persenjataan Ksatria Hijau","the golden knight's armaments":"Persenjataan Ksatria Emas",
        "the red knight's armaments":"Persenjataan Ksatria Merah","the black knight's armaments":"Persenjataan Ksatria Hitam",
        "mordred's armaments":"Persenjataan Mordred","esclados' sword and sheild":"Pedang dan perisai Esclados",
        "esclabor's sword and sheild":"Pedang dan perisai Esclabor","avalon-forged sword and shield":"Pedang dan perisai tempa Avalon",
        "camelot-forged sword and shield":"Pedang dan perisai tempa Camelot","pridwen and excalibur":"Pridwen dan Excalibur",
        "the green knight's sword":"Pedang milik Ksatria Hijau", "executioner's halberd":"Halberd Algojo",
        "red mist":"Kabut Merah", "blade of frenzy":"Bilah Amukan", "soulreaper":"Penuai Jiwa",
        "fleshripper":"Penyobek Daging", "bloodlust":"Haus Darah", "ragnarok":"Ragnarok",
        "bonesplitter":"Pemecah Tulang", "soulmyst blade":"Bilah Misteri Jiwa", "silent ruin":"Kehancuran Senyap",
        "steel breeze":"Angin Baja", "frostbite":"Gigitan Es", "stone of spiritual light":"Batu Cahaya Spiritual",
    }
    if low in special: return special[low]
    # Possessive names: translate the object first, then place the owner after it in Indonesian order.
    poss=re.match(r"^(.*?)['’](?:s)?\s+(.+)$",v,re.I)
    if poss:
        owner=poss.group(1).strip()
        tail=poss.group(2).strip()
        owner_low=owner.lower()
        owner_map={'high acolyte':'Akolit Agung','acolyte':'Akolit','executioner':'Algojo','the green knight':'Ksatria Hijau','the golden knight':'Ksatria Emas','the red knight':'Ksatria Merah','the black knight':'Ksatria Hitam','young tyler':'Tyler muda','chief makya':'Kepala Suku Makya','archangel micheal':'Malaikat Agung Michael','ancient royal guard':'Pengawal Kerajaan Kuno','dark elven high lord':'Penguasa Tinggi Elf Gelap','dark elven knight':'Kesatria Elf Gelap','dark elven general':'Jenderal Elf Gelap','captain of the guard':'Kapten Pengawal','royal court jester':'Badut Istana Kerajaan','royal consultant':'Penasihat Kerajaan','sun-chaser':'Pengejar Matahari','shadow warrior':'Prajurit Bayangan','mystic':'Mistik','warlock':'Penyihir Gelap','sorcerer':'Penyihir','nobleman':'Bangsawan','arch-angel':'Malaikat Agung','high assassin':'Pembunuh Ulung','demon hunter':'Pemburu Iblis','royal archer':'Pemanah Kerajaan','baby-dragon':'Bayi Naga'}
        owner_id=owner_map.get(owner_low,owner)
        if owner_low.startswith('sir '): owner_id=owner
        if tail.lower() in ('arms','armaments'): return f'Senjata {owner_id}'
        if tail.lower().endswith(' arms') or tail.lower().endswith(' armaments'):
            descriptor=tail.rsplit(' ',1)[0]
            descriptor_id=translate_modifiers(descriptor)
            return f'Senjata {descriptor_id} {owner_id}'
        if tail.lower() in ('sword and shield','sword and sheild'): return f'Pedang dan perisai {owner_id}'
        if tail.lower() in ('dagger','sword','bow','staff','wand','sceptre','scepter','cloak','belt','helm','armor','armour'):
            noun_map={'dagger':'Belati','sword':'Pedang','bow':'Busur','staff':'Tongkat sihir','wand':'Tongkat sihir','sceptre':'Tongkat kerajaan','scepter':'Tongkat kerajaan','cloak':'Jubah','belt':'Sabuk','helm':'Helm','armor':'Zirah','armour':'Zirah'}
            return f'{noun_map[tail.lower()]} {owner_id}'
        tail_id=translate_gear_name(tail)
        return f'{tail_id} {owner_id}'
    # A leading "X of Y" usually names an object by its property; move the item noun to the front.
    if ' of ' in low:
        parts=v.split(' of ',1); left,right=parts[0].strip(),parts[1].strip()
        left_words=left.split()
        noun_idx=None
        for j in range(len(left_words)-1,-1,-1):
            if left_words[j].lower() in GEAR_WORDS and GEAR_WORDS[left_words[j].lower()] in ('pedang lebar','pedang falchion','pedang','bilah','golok','kapak','tongkat sihir','tongkat','bola sihir','kalung','cincin','belati','busur','zirah','jubah','panji','tombak','tongkat kerajaan','perisai','pelindung dada','sepatu bot','helm','topeng','topi'):
                noun_idx=j; break
        if noun_idx is not None:
            noun=translate_atom(left_words[noun_idx])
            modifiers=translate_modifiers(' '.join(left_words[:noun_idx]))
            rhs=translate_modifiers(right)
            clean=' '.join(x for x in [noun,modifiers,rhs] if x).strip()
            clean=re.sub(r'\s+',' ',clean)
            return clean[:1].upper()+clean[1:]
    # Find a known item type at the end or near the end to get Indonesian noun-first order.
    low_words=low.split()
    for phrase, noun in sorted(OBJECTS,key=lambda p:len(p[0]),reverse=True):
        if low.endswith(phrase):
            prefix=v[:len(v)-len(phrase)].strip(' -')
            mods=translate_modifiers(prefix)
            # Do not add meaningless articles or conjunctions at the end of the modifier.
            mods=re.sub(r'\b(dan|dengan|of|the)\b','',mods,flags=re.I).strip()
            result=noun + ((' '+mods) if mods else '')
            return re.sub(r'\s+',' ',result).strip()
    # Common named object endings.
    suffix_map={'cleaver':'Golok','axe':'Kapak','pike':'Tombak','talwar':'Pedang talwar','sword':'Pedang','dagger':'Belati','dirk':'Belati','blade':'Bilah','staff':'Tongkat sihir','stave':'Tongkat sihir','rod':'Tongkat','orb':'Bola sihir','sceptre':'Tongkat kerajaan','scepter':'Tongkat kerajaan','crosier':'Tongkat uskup','polearm':'Senjata galah','crook':'Tongkat','bow':'Busur','gun':'Senapan','musket':'Senapan musket','rifle':'Senapan laras panjang','helm':'Helm','barbute':'Helm barbuta','hood':'Tudung','hat':'Topi','mask':'Topeng','coronet':'Mahkota kecil','mitre':'Mitra','headpiece':'Hiasan kepala','breastplate':'Pelindung dada','chestguard':'Pelindung dada','chestplate':'Pelat dada','platemail':'Zirah pelat','hauberk':'Zirah rantai','vest':'Rompi','robe':'Jubah','cloak':'Jubah','coat':'Mantel','tunic':'Tunik','gown':'Gaun','belt':'Sabuk','girdle':'Ikat pinggang','waistguard':'Pelindung pinggang','swathe':'Balutan','sash':'Selempang','cincture':'Ikat pinggang','clogs':'Sepatu kayu','sabatons':'Sepatu zirah','greaves':'Pelindung tulang kering','shoes':'Sepatu','boots':'Sepatu bot','drapes':'Kain jubah','cowl':'Penutup kepala','necklace':'Kalung','ring':'Cincin','talisman':'Jimat','pendant':'Liontin','bracelet':'Gelang'}
    for w in sorted(low_words,key=len,reverse=True):
        if w in suffix_map:
            idx=low_words.index(w)
            before=' '.join(v.split()[:idx]); after=' '.join(v.split()[idx+1:])
            mods=translate_modifiers((before+' '+after).strip())
            mods=mods.replace('  ',' ').strip()
            result=suffix_map[w]+((' '+mods) if mods else '')
            return re.sub(r'\s+',' ',result).strip()
    # For compound names that aren't identifiable, retain proper names and translate known terms only.
    out=translate_modifiers(v)
    out=re.sub(r'The','',out,flags=re.I)
    out=re.sub(r'\s+',' ',out).strip(' -')
    return out[:1].upper()+out[1:] if out else out

# Additional short safe replacements for tutorial/system copy found outside the dictionaries.
PHRASES = {
    'The Wastelands':'Tanah Tandus','Plains of Amesbury':'Dataran Amesbury','Dark forest of Linnuis':'Hutan Gelap Linnuis',
    'Twin peaks of\nFire and Water':'Puncak Kembar\nApi dan Air','Tomb of the Titans':'Makam Para Titan','Forgotten Garden':'Taman Terlupakan',
    'Lothian':'Lothian','Campaign':'Kampanye','Expedition':'Ekspedisi','Lucky Wheel':'Roda Keberuntungan','Boss Rush':'Tantangan Bos',
    'Ladder Match':'Pertandingan Peringkat','Card Gallery':'Galeri Kartu','Arena':'Arena','Trial by Fire':'Ujian Api',
}

SCENE_NAMES = ['Lothian','Tanah Tandus','Dataran Amesbury','Hutan Gelap Linnuis','Puncak Kembar\nApi dan Air','Astolat','Camelot','Makam Para Titan','Taman Terlupakan']
TOPONYMY_NAMES = ['Kapel Rosslyn','Haddington','Punggung Bukit Salisbury','Roxburgh','Sungai Dubglas','Pegunungan Eildon','Diffaith','Oasis Raja Nelayan','Halenstrad','Boscombe','Bukit Lark','Sungai Avon','Danau Viviene','Bonnymead','Kolam Ninianne','Hutan Ormsby','Beesby','Deepdale','Hutan Bain','Gunung Snowdon','Jembatan Menai','Sungai Lomond','Jalur Glaslyn','Tanchwa','Sungai Blackwater','Hutan Hangers','Astolat','Hutan Suci Druid','Benteng Timur','Winceastre','Jembatan Pembantaian','Gerbang Besi Camelot','Benteng Camelot','Air Terjun Styx','Ngarai Mencekam','Jalur Kaki Titan']

# Mission catalogue has repeated numbered templates; translate the template, preserving IDs.
MISSION_PREFIX = {
    'Cleaning Up':'Bersih-Bersih', 'Desert Guerrilla':'Gerilya Gurun', 'Explore the Jungle':'Jelajahi Hutan',
    'Den of Blossoms':'Sarang Bunga', 'Volcano':'Gunung Berapi', 'Attack the Batallion':'Serang Batalion',
    'Invading':'Invasi', 'Deep Magic':'Sihir Mendalam'
}

def translate_mission(text, idx):
    if idx == '0': return 'Jumlah penyelesaian'
    if idx == '1': return 'Misi 1: Gunakan skill secara optimal untuk meningkatkan efektivitas bertarung.'
    if idx == '2': return 'Misi 2: Mengalihkan perhatian musuh dengan tepat adalah kunci kemenangan.'
    if idx == '3': return 'Misi hadiah: Para goblin bertahan sampai akhir. Kalahkan mereka sekaligus!'
    if idx == '4': return 'Misi hadiah: Jangan macam-macam dengan Hercules!'
    if idx == '5': return 'Misi hadiah: Berburu bonus memang menggiurkan, tetapi waspadalah terhadap badai pasir!'
    m = re.fullmatch(r'Trial\s+(\d+)', text, re.I)
    if m: return 'Ujian ' + m.group(1).zfill(2)
    m = re.fullmatch(r'Daily Quest:\s*(.*?)\s*(\d+)', text, re.I)
    if m:
        prefix, number = m.group(1).strip(), m.group(2)
        prefix = MISSION_PREFIX.get(prefix, prefix)
        return f'Misi Harian: {prefix} {number}'
    m = re.fullmatch(r'Daily Quest:Hundred Chops(\d*)\(Conditions:Destroy 100 enemies\)', text, re.I)
    if m: return f'Misi Harian: Tebas Seratus {m.group(1) or ""} (Syarat: kalahkan 100 musuh)'.replace('  ',' ').strip()
    m = re.fullmatch(r'Daily Quest:Beat\x27em in 100 seconds(\d*)\(Conditions:Less than 100 seconds\)', text, re.I)
    if m: return f'Misi Harian: Kalahkan dalam 100 Detik {m.group(1) or ""} (Syarat: kurang dari 100 detik)'.replace('  ',' ').strip()
    m = re.fullmatch(r'Daily Quest:Raid (\d+)\(Conditions: Clear-out level in time\)', text, re.I)
    if m: return f'Misi Harian: Serbuan {m.group(1)} (Syarat: selesaikan tahap dalam batas waktu)'
    m = re.fullmatch(r'Daily Quest:Killing Frenzy (\d+)\(Conditions: Kill enemies in time\.\)', text, re.I)
    if m: return f'Misi Harian: Amuk Pembunuhan {m.group(1)} (Syarat: kalahkan musuh dalam batas waktu)'
    m = re.fullmatch(r'Daily Quest:9 Lives(\d*)\(Conditions:Survive until the time is up\)', text, re.I)
    if m: return f'Misi Harian: Sembilan Nyawa {m.group(1) or ""} (Syarat: bertahan hingga waktu habis)'.replace('  ',' ').strip()
    m = re.fullmatch(r'Daily Quest:Hidden Killer(\d*)\(Conditions: Survive until the time is up\)', text, re.I)
    if m: return f'Misi Harian: Pembunuh Tersembunyi {m.group(1) or ""} (Syarat: bertahan hingga waktu habis)'.replace('  ',' ').strip()
    # Conservative replacement for any residual catalog title.
    return text.replace('Daily Quest:', 'Misi Harian: ').replace('Conditions:', 'Syarat: ')

# Main localization routine. Every text node is visited; all known content sections get translated.
def read_packed(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) < 6: raise ValueError(f'Berkas bukan XML Cocos terkemas: {path}')
    return zlib.decompress(data[4:])

def write_packed(path: Path, raw: bytes) -> None:
    path.write_bytes(len(raw).to_bytes(4, 'big') + zlib.compress(raw, 9))

def apply_array(section, values, label):
    children = list(section)
    if len(children) != len(values):
        raise ValueError(f'Jumlah terjemahan {label} tidak cocok: {len(children)} vs {len(values)}')
    for node, value in zip(children, values):
        node.text = value

# Native story dialogue does not reliably wrap long Indonesian lines.
# Insert explicit line breaks at word boundaries so the game does not clip text.
STORY_WRAP_MAX_CHARS = 44

def wrap_story_text(text: str, max_chars: int = STORY_WRAP_MAX_CHARS) -> str:
    if not text:
        return text
    output = []
    for line_no, raw_line in enumerate(text.splitlines()):
        line = raw_line.strip()
        if not line:
            output.append('')
            continue
        # Keep speaker names ("Eric:", "Daisy:", etc.) on their own line.
        if line_no == 0 and line.endswith(':'):
            output.append(line)
            continue
        current = []
        current_len = 0
        for word in line.split():
            next_len = current_len + (1 if current else 0) + len(word)
            if current and next_len > max_chars:
                output.append(' '.join(current))
                current = [word]
                current_len = len(word)
            else:
                current.append(word)
                current_len = next_len
        if current:
            output.append(' '.join(current))
    return '\n'.join(output)


def main():
    packed_source = STRING_DIR / 'us.xml'
    source_root = ET.fromstring(read_packed(packed_source))
    root = ET.fromstring(read_packed(packed_source))
    counts = {}
    global_missing=[]
    for section in root:
        name = section.tag
        if name == 'global':
            for node in section:
                key = node.attrib.get('key','')
                if key in GLOBAL:
                    node.text = GLOBAL[key]
                else:
                    global_missing.append((key,node.text or ''))
            counts[name] = sum(1 for n in section if n.text and n.text.strip())
        elif name == 'tips': apply_array(section, TIPS, name); counts[name]=len(TIPS)
        elif name == 'skill':
            skill_map = {'activeskilldescribe':ACTIVE_DESC,'passiveskilldescribe':PASSIVE_DESC,'superioractivedescribe':SUPERIOR_DESC,'gearskill':GEAR_SKILL_DESC,'cardskill':CARD_SKILL_DESC}
            for sub in section:
                if sub.tag in skill_map: apply_array(sub,skill_map[sub.tag],sub.tag)
            counts[name]=sum(len(list(s)) for s in section)
        elif name == 'heroname': apply_array(section,HERO_NAMES,name); counts[name]=len(HERO_NAMES)
        elif name == 'heronameOnly': apply_array(section,HERO_SHORT,name); counts[name]=len(HERO_SHORT)
        elif name == 'herodescribe': apply_array(section,HERO_DESC,name); counts[name]=len(HERO_DESC)
        elif name == 'activeskillname': apply_array(section,ACTIVE_NAMES,name); counts[name]=len(ACTIVE_NAMES)
        elif name == 'passiveskillname': apply_array(section,PASSIVE_NAMES,name); counts[name]=len(PASSIVE_NAMES)
        elif name == 'superioractivename': apply_array(section,SUPERIOR_NAMES,name); counts[name]=len(SUPERIOR_NAMES)
        elif name == 'gearname':
            for node in section: node.text=translate_gear_name(node.text or '')
            counts[name]=len(list(section))
        elif name == 'achievementname': apply_array(section,ACHIEVEMENT_NAMES,name); counts[name]=len(ACHIEVEMENT_NAMES)
        elif name == 'achievementdescribe': apply_array(section,ACHIEVEMENT_DESC,name); counts[name]=len(ACHIEVEMENT_DESC)
        elif name == 'scene_name': apply_array(section,SCENE_NAMES,name); counts[name]=len(SCENE_NAMES)
        elif name == 'toponymy': apply_array(section,TOPONYMY_NAMES,name); counts[name]=len(TOPONYMY_NAMES)
        elif name == 'storyline':
            missing=[]
            for node in section:
                idx=node.attrib.get('index','')
                if idx in STORY: node.text=wrap_story_text(STORY[idx])
                else: missing.append(idx)
            if missing: raise ValueError(f'Storyline belum diterjemahkan: {missing}')
            counts[name]=len(list(section))
        elif name == 'mission':
            for node in section: node.text=translate_mission(node.text or '',node.attrib.get('index',''))
            counts[name]=len(list(section))
        elif name == 'notices_desc': apply_array(section,NOTICES_DESC,name); counts[name]=len(NOTICES_DESC)
        elif name == 'store_desc': apply_array(section,STORE_DESC,name); counts[name]=len(STORE_DESC)
        elif name == 'card_name': apply_array(section,CARD_NAMES,name); counts[name]=len(CARD_NAMES)
        else:
            # Unknown section is intentionally left unchanged and listed in the QA report.
            counts[name]=sum(1 for n in section.iter() if n.text and n.text.strip())
    if global_missing:
        raise ValueError('Kunci global belum diterjemahkan ('+str(len(global_missing))+'): '+repr(global_missing[:30]))
    raw=ET.tostring(root,encoding='utf-8',xml_declaration=True)
    write_packed(STRING_DIR/'id.xml',raw)
    # Native game language enum only has 5 choices and index 4 points to de.xml; use that slot for Indonesian.
    write_packed(STRING_DIR/'de.xml',raw)
    # Keep readable editable source outside runtime assets.
    out_source=Path(__file__).resolve().parent/'translation-source'/'id.xml'
    out_source.parent.mkdir(parents=True,exist_ok=True); out_source.write_bytes(raw)

    # Language-selection title is read from the packed app config by native code.
    global_path=ROOT/'assets/public/config/global.xml'
    grow=ET.fromstring(read_packed(global_path))
    for node in grow.iter('title14'): node.text='Bahasa Indonesia'
    write_packed(global_path,ET.tostring(grow,encoding='utf-8',xml_declaration=True))
    # Update Java/Android language-dialog label. There is no sixth enum option in closed-source native code.
    updated=[]
    verified=[]
    for path in (ROOT/'res').glob('values*/strings.xml'):
        try: x=ET.parse(path); rs=x.getroot()
        except Exception: continue
        changed=False
        for node in rs.findall("string[@name='language_german']"):
            if node.text!='Bahasa Indonesia': node.text='Bahasa Indonesia'; changed=True
            verified.append(str(path.relative_to(ROOT)))
        if changed:
            x.write(path,encoding='utf-8',xml_declaration=True); updated.append(str(path.relative_to(ROOT)))
    # Remove any stale decoded runtime files accidentally left from earlier attempts.
    for stale in [STRING_DIR/'id.xml.decoded', ROOT/'assets/public/config/global.xml.decoded']:
        if stale.exists(): stale.unlink()
    # Verify all runtime placeholders against the original English locale before reporting success.
    placeholder_pattern=re.compile(r'%(?:0\d+)?(?:\.\d+)?[a-zA-Z%]|%[A-Z]')
    placeholder_mismatches=[]
    source_nodes=list(source_root.iter()); target_nodes=list(root.iter())
    if len(source_nodes)!=len(target_nodes): raise ValueError('Struktur XML berubah saat lokalisasi')
    for original_node, target_node in zip(source_nodes,target_nodes):
        source_tokens=sorted(placeholder_pattern.findall(original_node.text or ''))
        target_tokens=sorted(placeholder_pattern.findall(target_node.text or ''))
        if source_tokens != target_tokens and (source_tokens or target_tokens):
            placeholder_mismatches.append({'tag':original_node.tag,'attrs':original_node.attrib,'source':source_tokens,'target':target_tokens})
    if placeholder_mismatches:
        raise ValueError('Ketidaksesuaian placeholder: '+repr(placeholder_mismatches[:10]))

    summary = {
        'locale_file':'assets/public/config/string/id.xml',
        'runtime_alias':'assets/public/config/string/de.xml',
        'language_picker_label':'Bahasa Indonesia (uses former Deutsch slot)',
        'text_nodes_processed':sum(counts.values()), 'section_counts':counts,
        'global_missing':len(global_missing), 'resource_labels_updated':updated,
        'resource_labels_verified':sorted(set(verified)),
        'placeholder_nodes_checked':len(source_nodes), 'placeholder_mismatches':len(placeholder_mismatches),
        'storyline_entries':len(STORY), 'gear_names_translated_by_glossary':len(list(root.find('gearname'))),
        'limitations':['Native enum has no extra locale slot; German option is replaced in this build.', 'Text baked into bitmap images and hardcoded native-library strings is not localized by XML changes.', 'A rebuilt APK and on-device review are required to validate layout/line wrapping.']
    }
    (Path(__file__).resolve().parent/'INDONESIAN-LOCALIZATION-REPORT.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
