## 📝 Rejoin Installation Guide

## Percobaan watchdog (terpisah dari branch antrean)

Hentikan engine lalu jalankan:
```sh
cd ~/rejoin
git fetch origin trial/engine-watchdog
git switch -c trial/engine-watchdog --track origin/trial/engine-watchdog
sh run.sh
```
Monitor wajib sudah aktif dan webhook punya pesan status sebelumnya untuk tes Discord.
Di sesi kedua, tes hang memakai `kill -STOP "$(cat ~/rejoin/data/monitor.pid)"`.
Setelah lebih dari 5 menit, cek `data/watchdog_report.txt` dan pesan status Discord.
Pulihkan dengan `kill -CONT "$(cat ~/rejoin/data/monitor.pid)"`; jangan biarkan engine
tersuspend. Tes crash bisa dengan `kill -KILL "$(cat ~/rejoin/data/monitor.pid)"` saat
engine manual berjalan. Ctrl+C normal tidak boleh menghasilkan laporan crash baru.
Log dikirim berupa potongan disensor pada pesan yang sama, bukan file attachment penuh.
Upload gagal ditahan lokal; retry saat watchdog aktif. Hang tidak di-restart otomatis.
Jangan reboot/update selama tes: auto-update boot dapat mengambil main lagi. Branch ini
tidak memuat perubahan antrean di `trial/single-loading-slot`. Kembali setelah stop:
`git switch main`. Salinan boot terpasang baru berubah bila installer menyalinnya;
tes di atas memakai `run.sh`, bukan salinan boot lama.

## Antrean launch / Delta minta key

Heartbeat aktif: clone yang masih login menunggu heartbeat sesi baru sebelum clone berikutnya dibuka.
RSS tinggi bukan bukti siap, dan timeout tidak lagi memindahkan antrean ke jeda tetap.
Setelah `launchJoinTimeout` (0 berarti default 240 detik), dashboard menampilkan
alasan antrean ditahan. Urus key/executor sendiri; heartbeat masuk → lanjut otomatis.
Key di disk hanya petunjuk, bukan jaminan key valid. Username bentrok perlu diperbaiki.
Login dicek ulang tiap 30 detik saat menunggu heartbeat, atau lebih cepat setelah
proses mati terdeteksi dua kali berturut-turut. Terkonfirmasi belum login → jeda
`launchEmptyDelay` (default 5 detik), lanjut clone berikutnya tanpa force-stop.
FC saja atau hasil cek gagal/tidak pasti tidak melepas antrean.

Untuk lewati **satu** clone atau batalkan sisa antrean: buka sesi Termux kedua,
jalankan `cd ~/rejoin && lua main.lua`, pilih **Menu 14**. Monitor tetap jalan setelah
cancel; skip berarti kamu menerima risiko loading clone sebelumnya belum selesai.
Selama menunggu, bot/webhook tetap aktif, recovery clone lain menunggu.
Cookie inject Menu 7: stop monitor dulu, inject target, lalu Menu 1 untuk autojoin
target melalui antrean yang sama. Jika monitor aktif gunakan `/cookie inject` di bot
setelah antrean sebelumnya selesai. Jangan pilih Launch All jika hanya ingin target.

## 🤖 Bot Discord (opsional)

Kode bot ada di **[bot/](bot/README.md)** dan blueprint Render ada di
**[render.yaml](render.yaml)**. Kalau Render minta kartu, pakai Railway (bagian *Deploy Railway* di panduan bot). Ikuti panduan bot untuk membuat aplikasi Discord,
invite, mengisi env dan deploy. Setelah URL hosting tersedia, isi `remote_url.txt`
lalu push ke `main`; tiap device cukup memakai secret yang sama (menu `9` → `10`).
Cara paling gampang: **daftar HWID**. HWID device muncul di akhir installer / Menu `9`;
ketik `/hwid redeem hwid:<HWID>` di Discord, selesai — ga ada yang perlu diisi di Termux.
(Owner bot sekali isi env `HWID_USERS` + volume `DATA_DIR` di Railway.)
Mau berbagi bot sama temen tapi device-nya terpisah? Tambah env `OWNERS`
(`idDiscord:secret`, satu secret per owner) — tiap orang cuma lihat device miliknya.
Jalankan monitor supaya command diproses. Node/npm hanya dipasang di hosting bot;
installer, boot, dan auto-update device tetap dipakai seperti biasa.

Balasan bot seluruhnya ephemeral dan hanya untuk owner yang didaftarkan. Mulai
dengan `/devices`, `/status`, lalu `/screenshot`. Banyak device Redfinger boleh
berbagi IP: pembatas 60 request/menit per IP hanya berlaku untuk auth gagal.
Command yang timeout tetap antre dan dijalankan ketika device online lagi.
Selama monitor jalan, command dari bot dikerjain ±1–2 detik setelah dikirim (device
long poll ke `/api/poll` di sela siklus monitor). Butuh bot versi terbaru: deploy ulang
bot di Railway; bot lama tetap jalan, cuma balik ke jeda `remote.interval`.

Menu `9` → `11` (Tes koneksi bot) hanya memeriksa autentikasi, jadi command yang
antre tetap menunggu monitor. Update deployment bot bersama engine agar endpoint
`/api/ping` tersedia; bot lama akan menampilkan pesan perlu update (HTTP 404).
Kalau memakai volume dan channel HWID bersamaan, `/hwid remove` menghapus kedua
salinannya; kegagalan menghapus pesan channel ditampilkan supaya bisa dicoba ulang.

Setelah launch/recovery, clone yang masih hidup tanpa heartbeat diberi waktu loading
minimal 60 detik (`gracePeriod` lebih besar juga dipakai). Kick/proses mati tetap
ditangani. Mengubah preset clone ke `d` (ikut default) di Menu `2` → `3` langsung
tersimpan tanpa perlu mengubah nama atau package.

## ⚡ Step 1: Root, Termux & Termux:Boot
1. **Root** harus aktif (**Magisk** / **KernelSU**). Buka **Superuser** → pastikan **Termux** diizinkan.
2. Install **[Termux](https://f-droid.org/packages/com.termux/)** dan **[Termux:Boot](https://f-droid.org/packages/com.termux.boot/)** dari **sumber yang sama** (dua-duanya F-Droid, atau dua-duanya GitHub).
   *Termux:Boot itu aplikasi (APK), bukan paket — `pkg install termux-boot` memang selalu gagal.*
3. Buka **Termux**, lalu izinkan akses storage (dibutuhkan untuk folder Delta):
💻 Desktop Copy:
```bash
termux-setup-storage
```
📱 Mobile Copy:
`termux-setup-storage`
*Pilih **Izinkan** saat diminta.*

## 📦 Step 2: Install (1 perintah)
💻 Desktop Copy:
```bash
curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh
```
📱 Mobile Copy:
`curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh`

Tunggu sampai muncul **SELESAI**. Installer mengerjakan 8 langkah dan menandai tiap langkah `[OK]` / `[!!]`:
1. Paket Termux (`lua53 sqlite curl git`) — dilewati kalau sudah lengkap, jadi install ulang cepat
2. Perintah `lua`
3. Cek root
4. Download Rejoin ke `~/rejoin` (config lama tetap dipakai kalau install ulang)
5. **Setting device otomatis** + auto atur jendela floating (grid) dinyalakan: animasi mati, Developer options (*Force allow apps on external*, *Force activities to be resizable*, *Enable freeform windows*, *Enable non-resizable in multi-window*), Smallest width 600dp, izin Termux jalan di background (dialog *"always run in background"* tidak muncul lagi), mode senyap (semua volume 0, suara sentuh/getar/kunci layar/charging mati, notif pop-up mati biar ga nutupin clone, auto-rotate, lokasi, scan Wi-Fi/Bluetooth di background mati) — plus script heartbeat ke folder Autoexecute Delta
6. Cek clone di config terpasang di device
7. Script auto-start + auto-update saat boot
8. Aktifkan Termux:Boot (layar Termux:Boot bisa terbuka sendiri — kembali saja ke Termux)

*Ada `[!!]`? Ikuti petunjuk di baris itu, lalu jalankan perintah install lagi (aman diulang). Kalau `[!!]` di langkah 8: tap ikon Termux:Boot sekali, lalu install lagi.*
*Setelah selesai, **reboot sekali** supaya freeform/resizable aktif.*

## 🚀 Step 3: Run & Setup
💻 Desktop Copy:
```bash
cd ~/rejoin && lua main.lua
```
📱 Mobile Copy:
`cd ~/rejoin && lua main.lua`

1. **Instances** — menu `2`: sesuaikan package clone (mis. `com.apengjers.v3`) + link game / Private Server tiap clone.
2. **Jeda launch** — menu `3` → `13`: `launchJoinTimeout` (default 240 dtk: maks tunggu clone **masuk game** lewat heartbeat Delta sebelum clone berikutnya) dan `launchSettleDelay` (20 dtk, dipakai kalau heartbeat tidak ada), lalu `15) Save and Exit`.
3. **Jendela & Mode Hemat** — menu `10` (pilih nomor, langsung tersimpan):
   - Auto atur jendela floating (grid) — sudah **nyala** dari installer. Baris atas numpuk 80 px ke baris bawah biar menu Roblox sampai *More* kelihatan (pilihan `9`, 0 = grid biasa)
   - Heartbeat Delta (status dari dalam game, langsung rejoin kalau ke-kick)
   - **Executor** (pilihan `10`): biasanya ga perlu disentuh. Rejoin masang script heartbeat ke semua executor yang ada di `/sdcard` dan otomatis make executor yang lagi jalan (heartbeat paling baru, dicek tiap 5 menit). Pilihan ini cuma buat maksa pilih sendiri / ketik path.
   - Mode hemat (render 3D mati, FPS dibatasi, grafik rendah) + batas FPS
4. **Preset Game** — menu `11`: `1)` tambah preset (kode `A`, nama game, link). Preset pertama otomatis jadi **default** dan semua clone ikut. Joki game lain? Tambah preset `B`, terus `4)` kasih ke clone tertentu (khusus), atau `3)` jadiin `B` default buat mindahin semua clone yang ikut default. Kalau engine lagi jalan, clone yang diubah langsung di-rejoin satu per satu. Link lama tiap clone otomatis dijadiin preset pas update. Clone baru di menu `2` otomatis ikut default.
5. **Discord Webhook** (opsional) — menu `9`: `1)` paste URL webhook channel (Discord → Edit Channel → Integrations → Webhooks → New Webhook → Copy Webhook URL), isi `7) Nama device` (mis. nama di Redfinger, biar tiap device kebedain), lalu `6) Kirim tes sekarang`. Status di-update tiap 5 menit + screenshot, cuma satu pesan. Kalau **Delta minta key** (file license hilang), muncul baris 🔑 di pesan status itu.
   *Ganti / replace device?* Pakai URL webhook yang sama, lalu `8) Pakai pesan status lama` → paste link pesan status device lama (Discord: klik kanan pesan → Copy Message Link). Device baru meneruskan pesan itu, jadi tidak ada pesan yang nyangkut.
6. **Script** (opsional) — menu `6`: `1)` tambah script ke folder Scripts (atau `2)` dari loadstring URL), lalu `4)` masukkan ke Autoexecute biar jalan otomatis di semua clone. `5)` keluarin dari Autoexecute (script di Scripts tetap ada).
7. **Bot Discord** (opsional, kalau udah punya bot sesuai `docs/discord_bot_prd.md`) — menu `9` → `10)` secret (sama dengan `DEVICE_SECRET` di bot), lalu `11)` tes koneksi. URL bot bisa diisi manual di `9)`, atau taruh sekali di `remote_url.txt` di repo (push ke `main`): device yang URL-nya kosong otomatis ngambil dari situ, jadi tiap device cukup diisi secret. Perintah dari bot dijalankan selama monitor jalan.
8. **Start** — menu `5` (Launch All + Monitor) buat buka semua clone, atau menu `1` (Start Monitor) kalau clone udah jalan dan cuma mau nyalain monitor + bot lagi. Keluar: **Ctrl+C**.
*Clone yang sudah login dibuka duluan, satu per satu: tiap clone ditunggu sampai heartbeat-nya bilang masuk game, baru clone berikutnya. Clone yang belum login dibuka paling akhir dan tidak ditunggu.*

## 🔁 Auto Start & Update
Cukup **reboot** cloud phone: Rejoin otomatis **update dari GitHub** lalu jalan sendiri (±10 detik setelah boot, tanpa jendela Termux). Config kamu tidak tertimpa.

| Perlu | Perintah |
|---|---|
| Update manual tanpa reboot | `sh ~/rejoin/update.sh` |
| Stop engine yang jalan dari boot | `kill $(cat ~/rejoin/data/monitor.pid)` |
| Matikan auto-update | `touch ~/rejoin/data/no-auto-update` |
| Setting device ulang / kembalikan | `sh ~/rejoin/device_setup.sh` / `sh ~/rejoin/device_setup.sh --undo` (volume balik ke setengah, setting senyap balik ke bawaan Android) |
| Tampilan kekecilan / kegedean (default 600, angka tersimpan) | `SMALLEST_WIDTH=800 sh ~/rejoin/device_setup.sh` lalu buka ulang clone |
| Install ulang (config tetap) | perintah di Step 2 |

*Mau pakai menu manual saat engine boot sedang jalan? Stop engine boot dulu (perintah di atas), kalau tidak muncul pesan `engine lain masih jalan`.*

## 🛠️ Troubleshooting
| Masalah | Solusi |
|---|---|
| `CANNOT LINK EXECUTABLE ... libcurl` | `apt update && apt full-upgrade -y`, lalu ulangi install |
| `[XX] Root belum aktif` saat buka rejoin | Magisk/KernelSU → Superuser → izinkan Termux (Grant). Cek `su -c id` harus muncul `uid=0`, lalu `lua main.lua` lagi |
| `dpkg was interrupted` / installer gagal di langkah 1 | `dpkg --configure -a && apt --fix-broken install -y`, lalu ulangi install (installer terbaru membereskannya sendiri) |
| Device lama (abis replace) nyangkut di `/devices` | `/device remove device:<nama lama>` → konfirmasi. Cuma bisa buat device offline. Pakai HWID? Hapus juga `/hwid remove hwid:<HWID lama>` |
| Delta minta key | Ambil key sendiri dari Delta, terus masukin di menu `12` atau bot `/delta input-key` (popup privat). Abis itu semua clone dibuka ulang satu per satu |
| Liat semua device + clone + preset + script sekaligus | `/overview` (kosongin device = semua device) |
| Banyak alarm logout sekaligus | Isi spreadsheet pakai kolom `DEVICE, USN, TANGGAL, JAM` (contoh `docs/alarm_import_template.csv`), export CSV, `/alarm import file:<csv>` → cek preview → Terapkan |
| Pasang APK (clone / executor) di device baru | Menu `13`: tempel link GoFile → pilih nomor APK → otomatis download + install |
| Mau logout otomatis jam tertentu / inject cookie dari Discord | `/alarm set clone:Clone2 date:25/10 time:12:00` (WIB, `daily:True` buat tiap hari; monitor harus jalan). `/cookie inject clone:Clone2` → isi cookie di popup privat (device harus online) |
| Logout manual malah di-rejoin lagi | Pakai **Menu 7 → 4 Logout akun clone** atau bot `/clone logout`: cookie dihapus + engine langsung tau clone itu udah logout, jadi ga di-rejoin. (Dibuka lagi ke layar login cuma kalau `relaunchNoLogin` nyala.) |
| Inject Cookie sukses tapi clone tetep logout | Liat blok **Kemungkinan penyebab** di bawah `[VERDICT]`. Biasanya proteksi lokasi Roblox (cookie diambil dari negara lain, misal device server Taiwan) → login manual di clone itu, atau ambil cookie dari login di jaringan device itu. Kalau app ga baca cookie WebView → bandingin versi Roblox antar device |
| `apt update` gagal / 404 | `termux-change-repo` → **Mirror group** → **Mirrors in Asia**, lalu ulangi |
| Reboot tapi clone tidak terbuka | `cat ~/rejoin/data/boot.log` — kosong/tidak ada = Termux:Boot belum aktif: tap ikonnya sekali, cek `su -c "dumpsys package com.termux.boot \| grep stopped="` harus `stopped=false` |
| Launch All kebuka barengan | Pastiin cuma 1 engine (Menu `1`/`5` nawarin stop engine boot). Abis Launch All, Menu `4` → Enter → paste ke chat. Baris `beres dalam ...s (alasan)` nunjukin kenapa tiap clone ga ditunggu |
| **Ada error apa pun** | Dari Discord: `/report device:<device>` → file report langsung dateng (ga perlu buka Termux). Dari Termux: Menu `4` → Enter (report lengkap, otomatis ke-copy) → paste ke chat. Menu rusak? `cd ~/rejoin && lua main.lua --report`. Copy ke clipboard paling lancar kalau app **Termux:API** + `pkg install termux-api` terpasang; tanpa itu dicoba lewat terminal, dan file-nya tetep ada di `/sdcard/Download/rejoin-report.txt` |
| Status / login aneh | `grep -E "\[LOGIN\]\|\[STATUS\]" ~/rejoin/data/rejoin.log \| tail -40` |
| Jendela floating tidak di grid | `grep WINDOW ~/rejoin/data/rejoin.log \| tail` (dibetulkan otomatis saat clone dibuka ulang) |
| Notif key tidak pernah muncul | `grep KEY ~/rejoin/data/rejoin.log` — harus ada baris `file license Delta: <path>`. Tidak ketemu → isi `deltaLicensePath` di `config/config.lua` |
| Heartbeat Delta tidak jalan | `ls /sdcard/Delta/Workspace/rejoin/` harus ada `hb_<username>.txt` setelah masuk game (Delta harus sudah di-key) |
| Terminal nyangkut / Ctrl+C tidak mempan | `stty sane` |
| Notification bar hilang (Redfinger) | `su -c "cmd statusbar expand-notifications"` |

*Note: Grant Root permissions when prompted.*
