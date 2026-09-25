# WORKING.md - File Manager Pro (serah-terima proyek, versi detail)

Terakhir diperbarui: 25 Sep 2026. Perbarui bagian "Status" setiap selesai satu fase/sub-fase, lalu commit dan push ke GitHub.

## 1. Visi proyek
Satu aplikasi Android yang menggabungkan tiga hal: file manager, pengarsip ala ZArchiver (ZIP dan format lain), dan terminal/Termux, dengan akses folder terproteksi lewat Shizuku.
- Layout split-screen. Kiri: kolom bubble lingkaran tanpa teks (Root, Internal Storage, Android/data, Android/obb, Downloads, dst.). Kanan: daftar file.
- Saat ada operasi panjang (copy, move, delete, extract, compress), panel kanan berubah jadi terminal log real-time (latar hitam, teks hijau, log ASLI dari operasi, bukan karangan). Setelah selesai ada tombol "Back to files".
- Top bar: search, settings, ikon status Shizuku (merah/kuning/hijau), tombol terminal (popup terminal interaktif dan aksi "Buka di Termux").
- Gaya: minimalis, gelap/netral, ringkas seperti alat teknis, tanpa gradien atau animasi berlebihan. Aksen hijau (#8BC34A) untuk state aktif/terpilih.

## 2. Teknologi dan keputusan
- Flutter (Dart) + Kotlin native untuk bagian Android. Min SDK 26. Flutter 3.47.5, Dart 3.13.4.
- State: Riverpod. ZIP: paket `archive` (streaming, di Isolate). Terminal UI: `xterm` (+ `flutter_pty` jika layak). Izin: `permission_handler`.
- Log dari Kotlin ke Flutter: EventChannel. Panggilan biasa: MethodChannel.
- Shizuku: API resmi lewat Kotlin, operasi berprivilege lewat Shizuku UserService (bukan perintah shell sekali jalan).
- Struktur: Flutter UI -> layanan Dart -> Method/EventChannel -> Kotlin -> Shizuku UserService -> operasi file.
- Struktur folder: lib/ main.dart, models/, services/ (file_service.dart, operation_service.dart), state/ (app_state.dart), screens/home_screen.dart, widgets/ (bubble_menu, file_list_panel, terminal_panel, conflict_dialog, create_archive_dialog).

## 3. Lingkungan kerja
- Komputer: Windows (RDP sementara, dihancurkan setelah sekitar 6 jam). Semua kode HARUS dibackup ke GitHub: repo `fauzan-ridani/file_manager_pro` (private).
- Lokasi: Flutter `C:\src\flutter`, Android SDK `C:\AndroidStudioSDK` (atau `C:\Android\Sdk`), proyek `C:\file_manager_pro`, folder uji `C:\test_files`.
- Diuji dengan `flutter run -d windows` (folder Windows asli). Tidak ada emulator Android. Shizuku, izin storage Android, Android/data, dan Termux HANYA bisa dites di HP Android asli.
- IDE agen: Antigravity. Kuota model terbatas, pakai model ringan untuk tugas biasa, model kuat hanya untuk Fase 4.
- Ada perbaikan build Windows di `windows/CMakeLists.txt`: `add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)` (untuk permission_handler + Visual Studio baru). Sudah ada di repo, jangan dihapus.

## 4. Status fase
- Fase 1 (UI statis): selesai.
- Fase 2 (browsing nyata, rename, hapus, seleksi, izin storage): selesai, lolos tes.
- Fase 3A (copy/cut/paste/delete + terminal log + Cancel + konflik Replace/Skip/Keep both): selesai, lolos tes.
- Fase 3B (ekstrak ZIP, zip-slip, ZIP rusak/palsu, cancel): selesai, lolos tes.
- Fase 3C (select all/clear/invert, Compress to ZIP, ekstrak banyak ZIP): selesai, lolos tes.
- Bugfix: compress ke ZIP dengan nama sudah ada dulu menampilkan opsi Replace dan menghapus ZIP lama sebelum yang baru selesai ditulis (file bisa hilang). Sudah diperbaiki: pakai Keep both/Skip (tanpa Replace), dan tulis ke file sementara baru rename setelah sukses. SELESAI, dikonfirmasi.
- Fase 3D (tombol + New folder/File/ZIP, info detail (i), jumlah isi folder "N items"): selesai, lolos tes semua sub-fase (3D-1, 3D-2, 3D-3).
- Fase 3E (popup "Jenis Tampilan": view mode/sort/hidden toggle, persist ke SharedPreferences): selesai, lolos tes.
- Fase 3F (dialog "Buat Arsip", ZIP-only, opsi lain disabled "Coming soon"): selesai, perbaikan kompresi folder kosong, verifikasi ZIP andal, dan pembungkusan Material ListTile telah diterapkan.
- BERIKUTNYA setelah 3F selesai: Fase 3G, lalu Search, Fase 4, Fase 5, Settings, Fase 6 (opsional).

## 6. Rencana fase berikutnya (detail)

### Fase 3G - Archive Viewer (ZIP-only untuk sekarang)
Tap file ZIP membuka layar baru menampilkan isinya tanpa ekstrak.
- List entry: nama, ukuran, tanggal modifikasi. Navigasi folder di dalam arsip (breadcrumb, tombol back ke parent).
- Long-press masuk mode seleksi (checkbox multi-select).
- Mode seleksi menampilkan FAB vertikal (hijau): Add file, Add folder, Cancel/close.
- Entry yang sudah ada di arsip, saat dipilih: Copy (ekstrak ke lokasi lain), Delete (rebuild arsip tanpa entry itu, dengan progress indicator), Rename, Extract here, Extract to.
- Untuk format yang tidak bisa ditulis nanti (7z/rar sebelum didukung penuh): sembunyikan aksi tulis (Add/Delete), hanya izinkan Copy/Extract.
- Pecah jadi beberapa prompt kecil saat dikerjakan (list+navigasi dulu, baru add, baru delete).

### Jalur riset terpisah (tidak menghalangi fase manapun)
- Sedang menyelidiki paket `koni_archive` (koni_zip, koni_sevenz, koni_rar, koni_codecs) yang mengklaim dukungan murni-Dart untuk 7z/RAR/tar + enkripsi AES tanpa native/FFI.
- HATI-HATI: paket sangat baru (~1 bulan), unverified publisher, ~0-2 likes, ~200 unduhan, belum ada rekam jejak. JANGAN dipakai di file_manager_pro dulu.
- Uji di proyek Flutter percobaan terpisah dulu: round-trip zip/7z/rar dengan password asli, verifikasi hasilnya bisa dibuka di 7-Zip/WinRAR sungguhan, sebelum dipertimbangkan untuk Fase 6.

### Search
- Cari nama di folder aktif, opsi rekursif. Berjalan di Isolate, ada progress dan Cancel. Filter: ekstensi, ukuran, tanggal. Hasil di panel kanan (bisa dibuka lokasinya). Di folder terproteksi, pencarian lewat Shizuku baru setelah Fase 4.

### Fase 4 - Shizuku (paling sulit, pakai model kuat, kerjakan bertahap)
- 4.1 Persiapan Kotlin: dependensi `dev.rikka.shizuku:api` dan `:provider`, deklarasi `ShizukuProvider` di AndroidManifest.
- 4.2 Deteksi status: Shizuku terpasang (`moe.shizuku.privileged.api`, butuh `<queries>` di Android 11+), service berjalan (`pingBinder`), izin diberikan (`checkSelfPermission`). Listener binder received/dead. Kirim status ke Flutter, tampilkan di ikon top bar (merah/kuning/hijau).
- 4.3 Alur izin: dialog penjelasan, `requestPermission`, tangani penolakan dan "jangan tanya lagi", tangani service mati tanpa crash.
- 4.4 UserService (AIDL): list, stat, rename, delete, mkdir, copy, move, baca/tulis stream. Data besar TIDAK lewat Binder biasa (batas ~1 MB): pakai stream/ParcelFileDescriptor, kirim progress saja.
- 4.5 Jembatan Flutter: MethodChannel untuk perintah, EventChannel untuk progress/log. `shizuku_service.dart` dengan antarmuka sama seperti `file_service` supaya UI tidak peduli sumbernya.
- 4.6 Integrasi: bubble Android/data dan Android/obb pakai Shizuku hanya jika API biasa tidak bisa. Fallback ke API biasa bila Shizuku tidak ada. Jangan pernah mengasumsikan Shizuku tersedia.
- 4.7 Batasan jujur: Root (/) tanpa root asli hanya baca sebagian. Pakai UserService, bukan `Shizuku.newProcess`. Fitur yang tidak bisa diuji tanpa HP: sebutkan langkah tes manual, jangan klaim sudah jalan.

### Fase 5 - Terminal interaktif dan Termux
- Tombol terminal di top bar membuka terminal interaktif (`xterm`). Folder kerja mengikuti folder aktif.
- Jika Shizuku aktif: shell lewat UserService (stdin/stdout stream). Tanpa Shizuku: shell aplikasi biasa dengan peringatan hak akses terbatas.
- "Buka di Termux": intent `com.termux.RUN_COMMAND`, cek Termux terpasang dan `allow-external-apps=true`.
- Terminal interaktif berbeda dari panel log operasi (read-only). Keduanya tetap ada.

### Settings (dikerjakan terakhir)
- Tampilkan file tersembunyi, urutan daftar, ukuran font terminal, batas baris log (~5000), folder tujuan ekstrak default, status Shizuku + tombol izin, panduan setup Termux, tema/kepadatan.

### Fase 6 - Opsional ala ZArchiver (belum dipastikan layak)
- Dukungan 7z/rar/tar.xz/tar.lz4/tar.zstd, enkripsi ZipCrypto/AES, split volume di dialog Buat Arsip dan Archive Viewer — bergantung hasil riset `koni_archive` di atas.
- Ekstrak sebagian entri saja, lihat arsip non-ZIP tanpa ekstrak.

## 7. Aturan perilaku aplikasi (sudah diterapkan, jangan dilanggar)
- Tidak pernah menimpa file diam-diam. Rename/create/copy memakai helper konflik nama di `file_service.dart`. Format nama salinan: `nama (1).ext`.
- Copy di folder yang sama: hanya Keep both / Skip (tanpa Replace). Cut di folder yang sama: tidak melakukan apa-apa, tampilkan "Already in this folder".
- Validasi nama: tidak kosong, tanpa `/ \ < > : " | ? *`, bukan hanya titik. Ganti huruf besar/kecil pada nama sama diperbolehkan.
- Jangan pernah menghapus file asli sebelum file pengganti selesai ditulis dengan sukses (tulis ke file sementara, rename setelah sukses).
- Status operasi: Done (hijau) hanya jika minimal satu item diproses dan tidak ada yang gagal. Nol diproses = "Nothing done" + alasan. Ada yang gagal = "Completed with errors". Selalu cetak ringkasan processed / skipped / failed.
- Item yang dilewati/diabaikan harus dilaporkan (amber di log), tidak pernah diam.
- Log: hijau normal, merah error, amber peringatan. Maksimal ~5000 baris. Cancel harus bersih (hapus file setengah jadi).
- Snackbar: floating, 4 detik, `clearSnackBars()` sebelum tampil.
- ZIP: perlindungan zip-slip, tangani ZIP rusak/palsu/terenkripsi, satu entri gagal tidak menghentikan yang lain. Folder (termasuk folder kosong dan bersarang) harus bisa dikompres dan diekstrak dengan struktur yang sama persis dengan aslinya.
- Jangan pernah memalsukan fungsi. Kalau ada batasan format/library, tampilkan opsi UI-nya sebagai disabled berlabel "Coming soon", jangan berpura-pura berfungsi.

## 8. Aturan untuk agen (tempel di setiap prompt)
- Proyek sudah ada, JANGAN dibuat ulang. Baca `WORKING.md` dulu (terutama bagian "Status fase" dan "Masalah aktif"), lalu hanya file yang diperlukan. Jangan scan seluruh proyek.
- Jangan sentuh `android/`, `ios/`, `web/`, `windows/`, `test/` kecuali tugasnya memang meminta (Fase 4-5 akan menyentuh `android/`).
- Jangan jalankan `flutter build` atau aplikasinya. Jalankan `flutter analyze` sekali di akhir dan perbaiki error.
- Tulis file langsung, tanpa perencanaan panjang. Perbarui `WORKING.md` (maksimal 3 baris tambahan, jangan hapus riwayat lama). Balasan akhir maksimal 3-6 baris lalu BERHENTI menunggu konfirmasi.
- Jangan pernah mengklaim fitur Shizuku/Termux sudah jalan sebelum dites di HP asli. Jangan pernah memalsukan log terminal — baris log harus dari operasi sungguhan.

## 9. Alur kerja dan backup
- Per (sub-)fase: jalankan prompt -> `flutter analyze` -> uji di Windows (`flutter run -d windows`, folder `C:\test_files`) -> laporkan per nomor tes -> prompt perbaikan singkat jika gagal -> backup.
- Backup: `cd C:\file_manager_pro`, `git status` (pastikan tidak ada file uji nyasar), `git add .`, `git commit -m "..."`, `git push`.
- Backup setiap selesai (sub-)fase. Kuota model tipis: pakai model ringan, minta revisi kecil dengan menyebut nama file.
- Aplikasi mengoperasikan file Windows ASLI. Uji hanya di `C:\test_files`, pastikan file uji tidak masuk folder proyek.

## 10. Masalah dan catatan lain yang diketahui
- Search dan Settings masih placeholder.
- Ikon bubble Root mirip ikon Shizuku di top bar (kosmetik, ganti nanti).
- Warning Git "LF will be replaced by CRLF" tidak berbahaya.
