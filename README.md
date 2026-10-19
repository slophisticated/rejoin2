# Rejoin Engine

Rejoin menjalankan dan menjaga banyak clone Roblox (App Cloner + Delta) di cloud phone Android yang sudah di-root. Ditulis dalam **Lua** dan jalan di **Termux**. Clone dibuka satu per satu, dipantau terus, dan langsung di-rejoin kalau ke-kick, freeze, atau force close. Data utama disimpan di device; kontrol Discord opsional memakai bot terpisah (Render atau Railway).

> Panduan langkah demi langkah yang siap dibagikan: **[setup.md](setup.md)**

> Bot Discord sekarang tersedia di **[bot/](bot/README.md)**: slash command ephemeral,
> screenshot, preset, multi-clone, setting, Scripts dan Autoexecute. Deploy lewat
> **[render.yaml](render.yaml)** atau Railway ([panduan](bot/README.md#deploy-railway)); Node/npm hanya diperlukan di hosting bot, bukan di device.

---

## ⚡ Install (1 perintah)

**Yang perlu disiapkan dulu:**
- Root aktif (**Magisk** / **KernelSU**).
- **Termux** dan **Termux:Boot** dari sumber yang **sama** (dua-duanya F-Droid, atau dua-duanya GitHub).
- Di Termux, jalankan `termux-setup-storage` lalu pilih **Izinkan**.

**Install, atau update dari versi lama:**
```sh
curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh
```

Tunggu sampai muncul **SELESAI**, lalu **reboot sekali**. Tiap langkah ditandai `[OK]` atau `[!!]`:

1. Paket Termux (`lua53 sqlite curl git`). Dilewati kalau semuanya sudah terpasang dan jalan, jadi install ulang cuma belasan detik. Paksa upgrade: `curl -sL .../install.sh | FULL_UPGRADE=1 sh`
2. Perintah `lua`
3. Cek root
4. Download Rejoin ke `~/rejoin`. Kalau folder lama sudah ada (termasuk hasil `git clone` dulu), config dan log tetap dipakai, jadi **tidak perlu `rm -rf`**.
5. Setting device: animasi mati, freeform / resizable / *force allow on external*, smallest width 600dp, dan izin Termux jalan di background
6. Cek clone yang ada di config, menyalakan auto atur jendela, dan memasang script heartbeat ke Autoexecute Delta
7. Script boot (auto-update + auto-start)
8. Mengaktifkan Termux:Boot

**Yang otomatis di-allow:** dialog *"Let app always run in background?"*, aktivasi Termux:Boot, dan Developer options.
**Yang tetap perlu tap sekali:** izin root di Magisk (pilih *Grant*) dan izin storage (`termux-setup-storage`).

Perintah yang sama aman dijalankan ulang kapan saja. Setelah install, **tidak perlu `git pull` lagi**: setiap boot, Rejoin update sendiri dari GitHub, lalu langsung jalan.

---

## Fitur

- **Launch All berurutan.** Clone dibuka satu per satu. Clone berikutnya baru dibuka setelah clone sebelumnya **benar-benar masuk game**: karakter sudah spawn dan aset selesai dimuat (lewat heartbeat Delta). Clone yang **sudah login dibuka duluan** (urut sesuai Menu 2), clone yang belum login dibuka **paling akhir** dengan jeda 5 detik.
- **Auto rejoin.** Clone yang ke-kick, disconnect, freeze, atau force close dibuka ulang dan masuk ke game / private server lagi. Setelah launch/recovery, proses yang masih hidup tanpa heartbeat diberi waktu loading minimal 60 detik (atau `gracePeriod` kalau lebih besar), supaya penurunan RSS tidak memicu restart berulang. Kick, heartbeat yang berhenti, dan proses mati tetap ditangani.
- **Heartbeat Delta.** Script di Autoexecute Delta melaporkan status dari dalam game: in-game atau ke-kick, FPS, ping, dan memori. Kalau ke-kick, langsung rejoin tanpa menunggu.
- **Mode hemat.** Render 3D mati, FPS dibatasi, grafik paling rendah, suara mati. CPU dan RAM per clone turun banyak.
- **Auto atur jendela.** Jendela floating clone disusun jadi grid (4 clone → 2×2). Baris atas sedikit lebih tinggi supaya menu Roblox kelihatan sampai *More*. Posisi dicek terus.
- **Preset game + preset default.** Simpan link tiap game sebagai preset (mis. `A` = Steal an Egg, `B` = Fisch) dan pilih satu jadi **default**. Semua clone ikut default, kecuali yang dikasih preset khusus. **Ganti game semua clone = ganti default sekali** (Menu `11`). Rejoin-nya berurutan biar RAM ga numpuk. Link lama tiap clone otomatis dijadiin preset pas update.
- **Kontrol dari bot Discord.** Semua setting (preset, pindah game, clone, webhook, nama device, ganti device, jendela, mode hemat, jeda launch) bisa diatur dari slash command dengan balasan ephemeral. Device yang nanya ke bot tiap ±30 detik, jadi ga perlu IP publik dan bebannya cuma 1 request kecil. Bot-nya dibuat terpisah (spesifikasi: [docs/discord_bot_prd.md](docs/discord_bot_prd.md)), sambungin di Menu `9` → `10` cukup **daftarin HWID** sekali: `/hwid redeem hwid:<HWID>` di Discord (HWID ada di Menu `9` / akhir installer), ga ada yang perlu diisi di Termux. Secret lama masih bisa. URL bot diisi di `9`, atau taruh sekali di `remote_url.txt` di repo: device yang URL-nya kosong ngambil sendiri dari situ.
- **Laporan Discord webhook.** Satu pesan status di-update tiap 5 menit (RAM, CPU, suhu, uptime, dan memori per clone + screenshot), plus notif **🔑 Delta minta key** kalau file license Delta hilang. Tiap pesan diberi nama device (diisi di Menu 9).
- **Cek login.** Akun diverifikasi ke Roblox. Clone yang belum login **tidak pernah di-force-stop**, tapi dibuka lagi kalau tertutup.
- **Auto start + auto update saat boot** lewat Termux:Boot, tanpa jendela Termux. Config tidak tertimpa.
- **Setting device otomatis.** Animasi, freeform, smallest width, dan izin background diatur sekali dari installer.
- **Dashboard live** dengan username tiap clone, status berwarna, FPS/RAM dari heartbeat, dan progres launch.
- **Inject Cookie.** Masukkan token `.ROBLOSECURITY` ke clone. Token diverifikasi dulu sebelum ditulis. Kalau abis inject clone tetep logout, menu ngasih tau kemungkinan penyebabnya (proteksi lokasi Roblox / app ga baca cookie WebView) plus negara IP device. Ada juga **Logout akun** (Menu `7` → `4` atau bot `/clone logout`): cookie dihapus, app ditutup, dan clone ga di-rejoin lagi. Enak buat ngurangin beban pas RAM/CPU spike. Bisa dijadwalin dari bot (`/alarm set`, jam WIB, sekali atau tiap hari), dan cookie bisa di-inject dari Discord lewat popup privat (`/cookie inject`).
- **Script Manager.** Script disimpan di folder **Scripts** Delta (tambah / ganti / hapus, bisa dari 1 baris loadstring URL). **Autoexecute ngambil dari Scripts**: masukin = copy dari Scripts, keluarin = hapus copy-nya. Berlaku buat semua clone di device itu. Bisa dari Menu `6` atau bot Discord (`/script`, `/autoexec`).
- **Cek root di awal.** Kalau root belum diizinkan, `lua main.lua` langsung berhenti dengan petunjuk cara mengaktifkannya.
- **Prioritas rendah.** Clone di-`renice` / `ionice` supaya Termux dan sistem tetap responsif.

---

## Pemakaian

```sh
cd ~/rejoin && lua main.lua
```

| Menu | Isi |
|---|---|
| `1` Start Monitor | Pantau + sambungan bot, tanpa launch ulang clone yang lagi jalan |
| `2` Instances Manager | Package clone + link game / private server |
| `3` Settings | Pengaturan umum; `13` = jeda launch (`launchJoinTimeout`, `launchSettleDelay`, dst.) |
| `4` View Logs | Lihat `data/rejoin.log` |
| `5` Launch All + Monitor | Buka semua clone berurutan, lalu pantau |
| `6` Script Manager | Script di folder Scripts + masukin/keluarin dari Autoexecute (copy dari Scripts) |
| `7` Inject Cookie | Login clone pakai cookie, cek token, logout akun clone |
| `8` Dump Cookies (debug) | Cek baris cookie clone (value tidak ditampilkan) |
| `9` Discord (Webhook & Bot) | URL webhook, interval, screenshot, notif key, kirim tes, nama device, pakai pesan status lama, URL + secret bot, tes koneksi bot |
| `10` Jendela & Mode Hemat | Grid, heartbeat, mode hemat, batas FPS, tinggi tambahan baris atas |
| `11` Preset Game | Tambah/ubah/hapus preset, set preset default, atur clone (khusus / ikut default / link sendiri), semua clone ikut default (+ rejoin) |
| `0` Exit | |

Baris paling atas menu menampilkan versi, apakah device di-install pakai cara instan, dan apakah auto-start boot aktif. Keluar dari monitor: **Ctrl+C**. Perubahan di menu 9 dan 10 langsung tersimpan.

Menu `9` → `11` hanya mengecek autentikasi bot, tanpa mengambil atau menjalankan
antrean command. Tes ini membutuhkan bot terbaru (`POST /api/ping`); kalau bot lama
membalas 404, update deployment bot. Di Menu `2` → `3`, pilihan `d` (ikut default)
tetap tersimpan walaupun nama/package tidak diubah.

---

## Perintah berguna

| Perlu | Perintah |
|---|---|
| Update manual tanpa reboot | `sh ~/rejoin/update.sh` |
| Cek versi | `git -C ~/rejoin log --oneline -1` |
| Stop engine yang jalan dari boot | `kill $(cat ~/rejoin/data/monitor.pid)` |
| Matikan auto-update | `touch ~/rejoin/data/no-auto-update` |
| Matikan auto-start saat boot | `rm ~/.termux/boot/start-rejoin.sh` (install ulang untuk menyalakan lagi) |
| Setting device ulang / kembalikan ke bawaan | `sh ~/rejoin/device_setup.sh` / `sh ~/rejoin/device_setup.sh --undo` |
| Ganti smallest width (angka diingat) | `SMALLEST_WIDTH=700 sh ~/rejoin/device_setup.sh` |
| Update log ke Discord (template: `tools/update_log_template.lua`) | Otomatis: taruh file di `tools/update_logs/` lalu push ke `main` (butuh secret repo `UPDATE_LOG_WEBHOOK`). Manual: `lua tools/update_log.lua <file> --send <webhook_url>` |
| Jalan tanpa menu (seperti boot) | `cd ~/rejoin && lua main.lua --headless --start-monitor --auto-launch` |

Hanya satu engine yang boleh jalan. Kalau engine dari boot masih aktif dan kamu buka menu `1` / `5`, muncul pesan `engine lain masih jalan`. Stop dulu engine boot-nya dengan perintah di atas.

---

## Konfigurasi

Semua bisa diatur dari menu. Isinya tersimpan di `config/config.lua` dan tetap aman saat update atau install ulang.

Link game per clone (`privateServer`) menerima:

| Jenis | Contoh |
|---|---|
| Game publik | `https://www.roblox.com/games/107778070777162/Steal-An-Egg` |
| Private server | `https://www.roblox.com/share?code=62e6ddb1dc13094d872ea3f91ec427c8&type=Server` |
| Deep link | `roblox://experiences/107778070777162` |

Link game publik otomatis diubah ke deep link supaya langsung join. Link private server dibuka apa adanya.

---

## Troubleshooting

Tabel lengkap ada di **[setup.md](setup.md)** (bagian Troubleshooting). Log yang paling sering dipakai:

```sh
cat ~/rejoin/data/boot.log                                               # boot / auto-update
grep -E "\[LOGIN\]|\[STATUS\]" ~/rejoin/data/rejoin.log | tail -40       # status & login
grep -E "launching|in game|heartbeat" ~/rejoin/data/rejoin.log | tail -20 # urutan Launch All
```

Riwayat perubahan: **[docs/changelog.md](docs/changelog.md)**.

Ngembangin pake AI agent (opencode, dll)? Konteks project, aturan teknis, dan alur kerja ada di **[AGENTS.md](AGENTS.md)**.

---

## Struktur project

```
rejoin/
├── main.lua            # entry point + main menu
├── install.sh          # installer 1 perintah
├── update.sh           # auto-update (dipanggil saat boot)
├── termux-boot.sh      # engine saat boot (restart otomatis)
├── device_setup.sh     # setting device (root)
├── run.sh              # pengawas terminal (Ctrl+C)
├── config/             # config.lua (punyamu) + template.lua
├── core/               # menu & config
├── managers/           # monitor, recovery, heartbeat, webhook, window_layout, auth, ...
├── scripts/            # rejoin_heartbeat.lua (dipasang ke Autoexecute Delta)
├── utils/              # shell, file, timer, ...
└── data/               # log & status runtime (rejoin.log, boot.log, monitor.pid)
```

---

## Lisensi / Kontribusi

Rejoin dirilis dengan lisensi **GNU GPL v3.0 atau lebih baru** ([LICENSE](LICENSE)). Bebas dipakai, dipelajari, diubah, dan dibagikan; versi modifikasi yang dibagikan atau dijual **wajib** tetap open source dengan lisensi yang sama dan mencantumkan sumber aslinya.

Mau kontribusi? Baca **[CONTRIBUTING.md](CONTRIBUTING.md)** (cara tes, gaya kode, aturan penting) lalu kirim pull request.

Gunakan dengan bijak sesuai ketentuan platform Roblox dan kebijakan masing-masing perangkat.
