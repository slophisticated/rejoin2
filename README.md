# Rejoin — versi publish

Engine Lua 5.3 di Termux untuk membuka dan menjaga clone Roblox App Cloner + Delta.
Branch `rejoinversifinal` dimulai dari main `apengjers/rejoin` (`d0de119`) dan memuat
fitur serta perbaikan rejoin2. Main rejoin2 tidak diubah.

## Loader 1 file

Untuk mencoba branch ini:

```sh
curl -fL -o /sdcard/Download/yanamin.lua https://raw.githubusercontent.com/slophisticated/rejoin2/rejoinversifinal/yanamin.lua
lua /sdcard/Download/yanamin.lua
```

Siapkan root Magisk/KernelSU, Termux dan Termux:Boot dari sumber yang sama, lalu
jalankan `termux-setup-storage` dan beri izin. Loader tidak membutuhkan folder source
atau Node di device. Setelah masuk repo apeng, URL download bisa memakai
`https://raw.githubusercontent.com/apengjers/rejoin/main/yanamin.lua`.

## Data root `/sdcard/yanamin`

Loader dan source modular memakai config dan state yang sama:

- `/sdcard/yanamin/config/config.lua`: akun/package, preset, heartbeat, webhook/bot.
- `/sdcard/yanamin/data/`: log, PID engine, HWID, request rejoin dan ID pesan webhook.
- `/sdcard/yanamin/launch.log`: diagnostik proses, maksimal sekali per 30 detik.

`YANAMIN_HOME` bisa mengganti root saat debugging. Config lama di working directory
hanya dipindahkan bila tujuan belum ada; config yang sudah ada tidak ditimpa.
Folder Scripts/Autoexecute/Workspace Delta tetap di lokasi Delta, dipakai bersama
semua clone dalam satu device. Heartbeat memakai username unik tiap clone.

## Antrean heartbeat v3

Semua Launch All, recovery, restart bot dan perubahan preset berbagi **satu slot
loading**. Clone berikutnya menunggu **3 heartbeat baru dari sesi yang sama,
berjarak total minimal 20 detik**. Script melaporkan `loading` sampai karakter ada
dan antrean aset kosong selama 5 detik. Lewat waktu loading tidak dianggap siap.

Username dipetakan ke package dari config. File `start_<username>.txt` mengikat
package dan token sesi launch; `hb_<username>.txt` menggemakan sesi + sequence.
Heartbeat lama, akun berbeda, atau username terduplikasi tidak meloloskan antrean.

Timeout `launchJoinTimeout` (default 240 detik) menahan slot sebagai **Perlu dicek**.
Heartbeat yang akhirnya siap bisa melanjutkan antrean. License hilang tanpa
heartbeat siap menampilkan **Menunggu key**; ini dugaan perlu pemeriksaan, bukan
bukti layar Get Key. Isi key secara manual. Status key tidak diketahui tidak
dianggap key hilang. Dashboard dan bot tetap diperiksa selama menunggu.

**Tidak ada batas/gate RAM. RSS hanya informasi.** Recovery menggunakan proses mati,
kick, atau heartbeat ingame yang berhenti, dengan jeda retry 120 detik dan batas
3 percobaan. Clone belum login dibuka lembut tanpa force-stop. Mode hemat tetap
opsional; mulai dari 15 FPS dan rendering 3D mati jika cocok untuk gamenya.

## Menu

| Nomor | Fungsi |
|---|---|
| 1 | Launch All + Monitor |
| 2 | Instances Manager: Auto Detect Roblox/manual, edit, hapus |
| 3 | Settings; item 13 untuk deadline/polling launch |
| 4 | Script Manager: simpan di Scripts, copy ke Autoexecute |
| 5 | Inject Cookie, cek token, logout akun clone |
| 6 | Auto-boot Termux:Boot: pasang, cek status/log, lepas |
| 7 | Uninstall yanamin (ada konfirmasi dan daftar target) |
| 8 | Discord webhook & bot, nama device, pesan status lama, HWID |
| 9 | Jendela & Mode Hemat |
| 10 / 0 | Exit |
| 11 | Preset Game |
| 12 | Antrean & Heartbeat: stabilisasi, cooldown, batas retry |
| 13 | Start Monitor tanpa mengulang Launch All |

Ctrl+C menghentikan monitor. Untuk mencoba ulang clone yang ditahan, gunakan
bot `/restart clones:<clone>` atau hentikan monitor dan pilih Menu 1. Main Menu 13
mengamati proses yang sudah berjalan. Setelah update v3, buka ulang clone bertahap
agar script autoexecute baru berjalan. Akun/game yang belum spawn tetap menunggu.

## Bot dan webhook

Bot opsional ada di [bot/README.md](bot/README.md); kontrak device di
[docs/discord_bot_prd.md](docs/discord_bot_prd.md). Node hanya diperlukan di hosting
bot. Menu 8 memuat URL/secret bot dan tes koneksi; `/hwid redeem` menghubungkan device.
Bot juga dapat menjadwalkan auto-logout per clone lewat `/alarm set` pada tanggal dan
jam WIB, sekali atau setiap hari. Jadwal tersimpan di device dan dijalankan saat monitor aktif.
Cookie akun yang kamu miliki juga bisa dikirim lewat `/cookie inject` dengan input
privat, lalu pilih device dan clone. Monitor harus aktif dan antrean launch sedang kosong.
Tes koneksi memakai `/api/ping` tanpa mengambil command. Registry HWID melengkapi
ID pesan channel setelah restart dan mengonfirmasi kegagalan penghapusan.

Webhook mempertahankan pesan status yang sama di data root, uptime/counter restart
per clone, screenshot dan notif key. URL/token tidak ditulis ke log.

## Source modular dan update

```sh
cd ~/rejoin && lua main.lua
```

Installer publish default mengambil repo apeng. Untuk menguji branch ini:

```sh
curl -fsSL https://raw.githubusercontent.com/slophisticated/rejoin2/rejoinversifinal/install.sh | REPO_URL=https://github.com/slophisticated/rejoin2 REJOIN_BRANCH=rejoinversifinal sh
```

`update.sh` memakai branch checkout saat ini kecuali `REJOIN_BRANCH` diisi.
Loader satu file diperbarui dengan download ulang; boot loader dipasang lewat Menu 6.
Panduan lengkap dan troubleshooting: [setup.md](setup.md).

## Validasi dan build

```sh
lua tests/regressions.lua
lua tests/publish.lua
cd bot && npm ci && npm test
```

Sesudah mengedit source, dari root repo jalankan `node tools/bundle_loader.js`.
`node tools/bundle_loader.js --check` mengecek loader sama dengan source. Node tidak
diperlukan untuk menjalankan loader. Tes lokal memakai simulasi; loading dan RAM
aktual perlu diuji di Redfinger. Riwayat: [docs/changelog.md](docs/changelog.md).
