# Reboot Handling

Inti dari VDLU adalah memperbarui modul tanpa mem-flash ulangnya, dan, sedapat mungkin, tanpa reboot sama sekali. Sebagian besar file dalam sebuah modul dapat diganti selagi perangkat berjalan. Beberapa benar-benar tidak bisa, karena kernel atau proses zygote telah memetakannya dan tidak akan menyadari perubahan sampai boot berikutnya.

Tugas VDLU adalah membedakan kedua kelompok itu secara otomatis, menerapkan semua yang dapat dilakukannya dengan aman secara **live**, dan menunda hanya file yang benar-benar terikat-boot ke sebuah reboot yang ditandainya dengan jelas. Halaman ini menjelaskan caranya.

Untuk mekanika engine di bawah ini, lihat [[Engine]]. Untuk gambaran besar, lihat [[Architecture]].

## Mengapa tidak sekadar reboot setiap kali

Reboot adalah hal paling mahal yang dapat diminta sebuah update dari seseorang. Ia menginterupsi apa pun yang sedang mereka lakukan, ia memakan waktu semenit atau lebih, dan ia melatih orang untuk takut pada update. Updater inkremental yang baik seharusnya terasa tak kasat mata: Anda tap update, beberapa file berubah di bawah sistem yang berjalan, dan Anda sudah berada di versi baru.

Jadi VDLU membalik asumsi biasa. Default-nya live. Sebuah file ditunda ke reboot hanya ketika ia terbukti salah satu dari jenis yang terikat-kernel atau terikat-zygote, dan bahkan saat itu hanya file itu yang menunggu. Semua di sekitarnya tetap diupdate segera.

## Tiga class

Setiap file dalam feed diberi sebuah class. Producer dapat mengaturnya secara eksplisit dalam manifest, tetapi dalam praktik class diturunkan dari path, dan engine hanya akan pernah menaikkan sebuah file menuju `reboot`, tidak pernah menurunkannya menuju `live`. Class-nya adalah:

**LIVE** adalah kasus umum: aset web UI, biner, skrip yang dibaca sesuai permintaan, file config, `module.prop`, dan apa pun lainnya yang tidak cocok dengan aturan di bawah. File live dibackup lalu secara atomik di-rename di atas target selagi sistem berjalan. Tanpa reboot, dan perubahan berlaku pada saat rename mendarat.

**SOFT** adalah skrip lifecycle milik modul sendiri: `service.sh`, `post-fs-data.sh`, dan `boot-completed.sh`. Ini diterapkan live persis seperti file LIVE, jadi salinan baru sudah ada di disk. Alasan mereka mendapat class sendiri adalah bahwa sistem yang berjalan telah mengeksekusi salinan lama pada boot ini; yang baru cukup berjalan pada boot berikutnya, tanpa staging dan tanpa banner. Tidak ada yang perlu ditunda, hanya serah terima yang alami.

**REBOOT-hard** adalah himpunan kecil yang tidak dapat berubah di bawah sistem yang berjalan:

- library native, `*.so` (apa pun di bawah path `zygisk/`), karena zygote memetakannya ke dalam setiap app saat startup;
- file overlay `/system`, karena overlay di-mount saat boot;
- file `sepolicy.rule`, karena kebijakan SELinux dimuat lebih awal.

File REBOOT-hard tidak pernah dituliskan di atas inode live-nya selagi sistem menyala. Menimpa sebuah `.so` yang telah dipetakan zygote adalah cara Anda mendapatkan crash dan state yang tidak konsisten. Alih-alih, konten baru **di-stage** di samping direktori state dan di-swap masuk pada boot berikutnya, sebelum apa pun dapat memetakannya.

## Path ke class, sekilas

Engine menurunkan class dari path seperti ini:

| Pola path | Class | Diterapkan |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (file `.so`) | REBOOT-hard | di-stage, di-swap pre-zygote saat boot |
| `system/**` (overlay) | REBOOT-hard | di-stage, di-swap saat boot |
| `*.rule` (sepolicy) | REBOOT-hard | di-stage, di-swap saat boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | ditulis live, berjalan boot berikutnya |
| `webroot/**`, `bin/**`, `lib/**`, config, `module.prop`, semua lainnya | LIVE | ditulis live, efektif segera |

Manifest dapat membawa `class` eksplisit per file, tetapi class yang diturunkan bertindak sebagai batas bawah: jika sebuah file tampak REBOOT-hard berdasarkan path-nya, ia diperlakukan sebagai REBOOT-hard bahkan jika manifest mengatakan sebaliknya. Ini menjaga feed yang salah-label agar tidak pernah mencoba hot-swap sebuah `.so`.

## Bagaimana sebuah run menangani kedua kelompok sekaligus

Selama `run` biasa (siklus DIFF ke FETCH ke APPLY ke COMMIT yang dideskripsikan di [[Engine]]), kedua kelompok ditangani dalam transaksi yang sama:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Jadi setelah sebuah run yang menyentuh sebuah `.so`, Anda sudah berada di versi baru untuk setiap file live, dan hanya potongan yang di-stage yang menunggu. Journal melaporkan `reboot_pending`, dan WebUI menampilkan banner persisten yang mengundang reboot untuk mengaktifkan file yang di-stage. Tidak ada "done" palsu: sebuah run dengan file yang di-stage berakhir dalam `PENDING_REBOOT`, bukan `DONE`.

## Swap saat boot

File yang di-stage diterapkan oleh perintah `boot`, yang disambungkan host module ke `post-fs-data.sh` sehingga ia berjalan secara sinkron dan **pre-zygote**, sebelum proses apa pun dapat memetakan `.so` baru.

`boot` melakukan `resume` (untuk menyelesaikan fase yang terinterupsi apa pun) lalu swap. Untuk setiap file REBOOT-hard yang di-stage ia:

1. memastikan path yang di-stage tetap di dalam direktori modul (pemeriksaan containment);
2. me-re-hash `staged/<path>.vdlu-new` terhadap hash manifest;
3. membackup file live saat ini;
4. `mv -f` file yang di-stage di atas yang live dan `chmod`-nya;
5. me-re-hash file yang sekarang di tempat, untuk memastikan swap mendarat dengan benar;
6. menandainya diterapkan.

Hanya setelah setiap file yang di-stage telah di-swap dan di-re-verify transaksi menutup dari `PENDING_REBOOT` ke `DONE`. Jika ada langkah yang gagal, journal mencatat error dan modul mempertahankan file sebelumnya; tidak ada yang dibiarkan setengah-swap.

Karena swap adalah sekuens re-hash dan rename atomik, menjalankan `boot` aman bahkan jika ia terinterupsi terakhir kali. Ia cukup mengambil kembali file yang di-stage.

## auto_on_reboot

Staging hanyalah separuh dari rasa bebas-reboot; separuh lainnya adalah bahwa pengguna seharusnya tidak pernah harus ingat untuk menjalankan swap. Dengan `auto_on_reboot=1` dalam config, `post-fs-data.sh` host module memanggil `update.sh boot` pada setiap boot. Itu berarti:

- jika sebuah transaksi tertunda reboot, file yang di-stage di-swap masuk secara otomatis sebelum zygote mulai, dan pengguna sekadar mendapati dirinya sepenuhnya di versi baru;
- jika tidak ada yang tertunda, `boot` dapat menjalankan siklus baru dan menerapkan segalanya, termasuk sebuah `.so`, dalam satu boot itu, karena ia sudah berjalan pre-zygote.

Dengan kata lain, sebuah `.so` yang di-stage tidak menghabiskan biaya apa pun bagi pengguna selain reboot yang toh akan mereka lakukan. Mereka tidak harus men-tap apa pun untuk kedua kalinya.

## Offline saat boot, tanpa menguras baterai

Terkadang `boot` ingin memeriksa feed tetapi perangkat belum punya jaringan. VDLU dapat menunggunya, dengan sabar dan murah, dikendalikan oleh `boot_retry_minutes` (0 mematikannya). Menunggu itu sengaja hemat baterai:

- di antara percobaan ia cukup `sleep`, yang membeku dalam deep sleep, jadi perangkat tidur normal dan retry dilanjutkan hanya setelah perangkat sudah terbangun;
- ia tidak memegang wakelock dan tidak memegang lock engine selagi menunggu, jadi sebuah run manual tidak pernah diblokir;
- sebelum setiap percobaan ia memeriksa apakah jaringan diizinkan dengan kernel route lookup yang tidak mengirim paket dan tidak membangunkan radio;
- ia tidak pernah mencoba ulang kegagalan deterministik seperti signature buruk atau downgrade yang diblokir, hanya kondisi jaringan-absen yang asli.

Pemeriksaan manifest itu sendiri tetap gratis di jaringan apa pun, jadi Anda selalu tahu sebuah update ada; hanya download yang menunggu kebijakan jaringan dipenuhi, menunda dengan rapi alih-alih error.

## Lihat juga

- [[Engine]]: transaksi, logika apply-by-class, dan perintah `boot` secara penuh.
- [[Architecture]]: di mana engine duduk di antara producer dan WebUI.
