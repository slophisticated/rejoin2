# Rejoin Control Bot

Bot Discord untuk protocol `1` di `managers/remote.lua`. Gateway Discord dan API
HTTP berjalan dalam satu proses Node.js 24 + discord.js v14, tanpa database atau
framework HTTP. Device melakukan polling; bot tidak menghubungi device.

## Buat aplikasi dan invite

1. Buat aplikasi di [Discord Developer Portal](https://discord.com/developers/applications).
   Ambil **Application ID** dan **Bot Token**. Token hanya disimpan di env.
2. Aktifkan Developer Mode Discord untuk menyalin **Server ID** dan **User ID** owner.
3. Invite dengan scope `bot` dan `applications.commands`, permission View Channels,
   Send Messages, Embed Links, dan Attach Files. Administrator tidak diperlukan.
   Template: `https://discord.com/oauth2/authorize?client_id=APP_ID&scope=bot%20applications.commands&permissions=52224`.
   Ganti `APP_ID` dengan Application ID.
4. Bot hanya memakai intent `Guilds`; privileged intent tidak diperlukan. Kosongkan
   **Interactions Endpoint URL** karena interaction diterima melalui gateway.

## Deploy Render Free

Pilih **New → Blueprint**, repo `slophisticated/rejoin2`, branch `main`.
Blueprint `render.yaml` di root mengatur Web Service Node Free, root `bot`, build
`npm ci`, start `node src/index.js`, health `/health`, Node `24.20.0`, dan build filter
`bot/**`. Perubahan Lua tidak memicu redeploy bot.

| Env | Isi |
|---|---|
| `DISCORD_TOKEN` | Token bot Discord |
| `APP_ID` | Application ID |
| `GUILD_ID` | Server ID tempat command didaftarkan |
| `OWNER_IDS` | User ID yang boleh mengontrol, dipisahkan koma (1 akun bareng) |
| `DEVICE_SECRET` | Opsional (≥32 karakter): secret lama untuk `OWNER_IDS`; kosong = pakai daftar HWID |
| `HWID_USERS` | Opsional: ID Discord yang boleh `/hwid redeem`, masing-masing akun sendiri |
| `HWID_CHANNEL_ID` | Opsional: channel privat buat nyimpen daftar HWID kalau ga ada volume |
| `OWNERS` | Opsional, **device terpisah per owner**: `idDiscord:secret,idDiscord:secret` (lihat di bawah) |
| `PORT` | Otomatis dari Render; server listen `0.0.0.0` |
| `COMMAND_TIMEOUT_SEC` | Opsional, default `90` |
| `DATA_DIR` | Opsional, kosong pada Render Free |

**Daftar HWID (disarankan, tanpa secret).** User cukup paste HWID ke bot sekali.

1. Railway: pastikan Volume terpasang (mis. di `/data`) dan `DATA_DIR=/data`, supaya
   daftar HWID ga hilang tiap redeploy. Tanpa volume bisa pakai channel Discord privat:
   `HWID_CHANNEL_ID=<id channel>` (bot butuh izin View, Send Messages, Read History).
   Orang yang boleh daftar: `OWNER_IDS` (akun bareng) dan/atau `HWID_USERS=idDiscord,...`
   (masing-masing akun sendiri). `DEVICE_SECRET` boleh kosong.
2. Device: HWID muncul di akhir installer, di Termux `lua main.lua` → `9` (baris bot),
   atau `lua main.lua --hwid`.
3. Discord: `/hwid redeem hwid:<HWID>` → selesai. Device sync pakai header
   `X-Rejoin-Hwid` dan masuk ke list orang yang daftar. `/hwid remove hwid:<HWID>`
   buat nyabut.

Yang disimpan cuma hash HWID. HWID = "password" device: acak, tapi jangan disebar.

Volume dan channel boleh dipakai bersamaan. Registry memuat kembali ID pesan
channel sebelum menerima perubahan HWID, supaya `/hwid remove` tetap tercabut
setelah restart. Kalau channel belum siap atau penghapusan pesan gagal, command
menampilkan error; cek izin/koneksi bot lalu coba lagi. Kalau channel tetap belum
siap setelah startup, restart bot setelah izin/koneksinya diperbaiki.

Tes koneksi di Menu `8` → `11` memakai `POST /api/ping` dengan autentikasi HWID/secret
yang sama. Endpoint ini tidak mengambil antrean command, tidak mengirim ACK, dan
tidak mengubah snapshot/waktu sync. Deploy versi bot ini bersama engine terbaru;
engine menampilkan pesan update kalau endpoint belum tersedia di bot lama.

**Device per owner (`OWNERS`).** Tiap owner punya secret sendiri; device yang sync
pakai secret itu masuk ke akun owner tersebut. `/devices`, `/status`, autocomplete,
`device:all`, dan semua command cuma menyentuh device milik pemanggil. Nama device
boleh sama antar owner. Contoh 5 device punya kamu + 3 device temen:

```
OWNERS=111111111111111111:secretKamu32karakterAtauLebih,222222222222222222:secretTemen32karakterAtauLebih
```

Device kamu isi `secretKamu` di menu `8` → `10`, device temen isi `secretTemen`; URL
bot sama (`remote_url.txt`). Dua ID dengan secret yang sama = berbagi satu akun.
`OWNER_IDS` + `DEVICE_SECRET` tetap jalan (jadi satu akun tersendiri), jadi setup lama
tidak perlu diubah; tinggal tambah `OWNERS` buat owner baru. Akun dikenali dari secret,
jadi **ganti secret = device muncul sebagai akun baru**. Yang punya hosting tetap bisa
melihat data semua akun di server, jadi pakai hanya dengan orang yang dipercaya.

**Pindah hosting:** pakai kembali `DEVICE_SECRET` lama, jangan menggantinya dengan
secret baru hasil generate. Bot mendaftarkan command guild otomatis saat startup.
Log normal: `listening on :PORT` dan `logged in as <bot tag>`.

`GET https://<service>.onrender.com/health` mengembalikan
`{"ok":true,"devices":N}`, tanpa nama atau data device.
Render Free bisa tidur setelah sekitar 15 menit tanpa traffic masuk dan cold start
bisa sekitar satu menit. Sync device biasanya menjaga service aktif. Disarankan
monitor gratis UptimeRobot/cron-job.org **GET `/health` tiap lima menit** agar bot
tetap terjangkau saat semua device mati; batas kuota Render tetap berlaku.

## Deploy Railway

Alternatif kalau Render minta kartu. Railway pakai kredit trial; kalau kredit habis
service berhenti, pindah akun tinggal ulangi langkah ini.

1. **New Project → Deploy from GitHub repo** → `slophisticated/rejoin2` (kalau repo
   tidak muncul: *Configure GitHub App* → beri akses repo itu).
2. Service → **Settings**:
   - Root Directory: `bot`
   - Start Command: `node src/index.js` (build otomatis `npm ci`; Node 24 dibaca dari
     `engines` di `package.json`)
   - Healthcheck Path: `/health`
   - Watch Paths: `bot/**` (biar push kode Lua tidak deploy ulang)
   - Region: Asia/Singapore kalau tersedia
3. **Variables**: `DISCORD_TOKEN`, `APP_ID`, `GUILD_ID`, `OWNER_IDS`, `DEVICE_SECRET`
   (≥32 karakter). `PORT` diisi Railway sendiri.
4. **Settings → Networking → Generate Domain** → URL tetap
   `https://<service>.up.railway.app`. Cek `<url>/health` → `{"ok":true,"devices":0}`.
5. Isi URL itu di `remote_url.txt` lalu push (lanjut ke bagian berikut).

Railway tidak menidurkan service, jadi tidak perlu monitor uptime. **Pindah akun:** buat
`DEVICE_SECRET` yang **sama persis**, generate domain baru, ganti baris di
`remote_url.txt`; device pindah sendiri setelah 5x sync gagal (±10–20 menit).

## Sambungkan device

1. Setelah deploy, isi URL HTTPS sebenarnya di `remote_url.txt` pada root repo lalu
   push ke `main`. Device mengambil **URL HTTPS pertama**: jangan menaruh URL contoh
   di komentar sebelum URL yang benar.
2. Termux menu `8` → `10`: isi secret yang sama dengan `DEVICE_SECRET`.
3. Nama device = Menu `8` → `7` (sama dengan nama di webhook). **Isi unik per device**;
   kalau kosong dipakai model HP yang biasanya sama di semua Redfinger, dan `/devices`
   menandai ⚠️ kalau dua device online pakai nama sama. Ganti nama dari menu langsung
   dipakai engine yang jalan; entri nama lama di `/devices` hilang sendiri ±1 menit.
4. URL device boleh kosong agar diambil dari repo, atau diisi manual di `9` → `9`.
   URL yang diisi manual (mis. bot milik sendiri) **tidak pernah diganti** oleh
   `remote_url.txt`; isi `-` untuk kembali ikut repo.
5. `9` → `11`: tes koneksi; jalankan monitor (menu `1` Start Monitor, atau `5` Launch All).
6. Device terlihat di `/devices` pada sync berikutnya, default sekitar 30 detik.

Command diproses hanya saat monitor aktif. Setelah menerima command, device polling
tiap lima detik selama dua menit. Jika hosting pindah, ubah URL di `remote_url.txt`
dan pertahankan secret; setelah lima sync gagal device mencoba URL repo, dengan
pembacaan maksimal sekali per sepuluh menit. Cold start pertama boleh gagal karena
device akan mencoba lagi dengan backoff.

## Command

Seluruh balasan, file, tombol konfirmasi, dan follow-up **ephemeral**. Hanya user
dalam `OWNER_IDS` / `OWNERS` di `GUILD_ID` yang boleh memakai command, tombol, dan
autocomplete; tiap owner hanya melihat device akunnya.
Opsi `device` boleh kosong bila hanya satu device dikenal.

| Command | Fungsi |
|---|---|
| `/devices`, `/status` | Daftar device, status snapshot, Refresh dan pagination |
| `/game preset:B` | Semua clone ikut B; preset khusus dilepas, B jadi default |
| `/game preset:B clones:"Clone1,Clone3"` | Pindahkan clone pilihan ke preset khusus |
| `/default preset:A` | Ganti default; clone khusus tetap memakai preset sendiri |
| `/preset list/set/remove` | Kelola preset; default tidak bisa dihapus |
| `/clone list/add/edit/remove` | Kelola daftar; remove perlu konfirmasi, bukan uninstall |
| `/clone logout clones:"Clone2"` | Logout akun Roblox clone pilihan (cookie dihapus, app ditutup, ga di-rejoin). Konfirmasi dulu; `all` ga boleh |
| `/cookie inject device:<device> clone:<clone>` | Buka input privat untuk inject cookie ke satu clone; device harus online |
| `/alarm set` | Jadwalkan logout satu clone pada tanggal dan waktu WIB; sekali atau berulang tiap hari |
| `/alarm list/remove` | Lihat atau hapus jadwal logout per device/clone |
| `/restart clones:"Clone1,Clone3"` | Rejoin pilihan; `clones:all` = Launch All |
| `/screenshot` | Gambar layar cloud phone sekarang |
| `/config get/set` | Setting dari schema snapshot device |
| `/webhook set/options/test` | URL, interval, screenshot, notif key, hide names, tes |
| `/device rename/replace` | Ganti nama / teruskan pesan status lama |
| `/window`, `/saver`, `/launch` | Shortcut grid, heartbeat/mode hemat, jeda launch |
| `/script list/add/view/remove` | Gudang Scripts; view mengirim attachment |
| `/autoexec list/add/remove` | Copy dari Scripts atau hapus copy Autoexecute |

`device:all` didukung pada game/default, preset set/remove, screenshot, config set,
webhook set/options, window/saver/launch, script add/remove, autoexec add/remove.
Hasil dan validasi ditampilkan per item/per device, termasuk kegagalan parsial.
Clone boleh direferensikan dengan nama, ID, atau package; daftar berkoma didukung
autocomplete. Tambahan pilihan autocomplete memakai ID agar tidak ambigu.

`/clone edit preset:default` mengembalikan clone ke default; `preset:-` memakai link
sendiri. `link:-` menghapus link sendiri. Status menampilkan preset efektif/sumber,
link, FPS/memori, dan username spoiler jika `webhook.hideNames` aktif.

### Script dan screenshot

- `/script add name:farm` memakai **tepat satu** `file:`, `url:`, atau `code:`.
  Attachment harus `.lua`/`.txt`, teks UTF-8, maksimal **200 KiB**. Gunakan `code:`
  untuk teks pendek. URL HTTPS diteruskan ke device untuk dibuat loader, tidak
  diunduh bot.
- Nama memakai huruf/angka/`_-.`, tidak diawali titik, maksimal 64 karakter termasuk
  ekstensi. `.lua` ditambahkan jika belum berakhiran `.lua`/`.txt`.
- Isi masuk ke **Scripts**. `/autoexec add` hanya menyalin dari Scripts. Mengganti
  script memperbarui copy Autoexecute melalui handler device yang sudah ada.
  Folder berlaku untuk seluruh clone satu device. `rejoin_heartbeat.lua` dilindungi.
- PNG maksimal **8 MiB** dan hanya untuk screenshot yang sedang menunggu. Upload
  boleh sebelum/sesudah ACK; setelah ACK, tunggu maksimal 30 detik. Buffer hanya di
  memori, dihapus setelah terkirim atau lima menit. Banyak gambar dipecah sesuai
  batas ukuran Discord dan maksimal sepuluh file per pesan; semua tetap ephemeral.
- Cookie dikirim lewat modal privat, command bersifat sementara di memori bot, tidak
  ditulis ke `state.json`, tidak dicatat ke log, dan tidak dikirim ulang otomatis.
  Jika device belum menerima command dalam 90 detik, command dihapus dan perlu dikirim
  ulang. Setelah diterima, device memverifikasi token ke Roblox sebelum menulisnya ke
  Cookies DB. Gunakan hanya cookie akun milikmu.
- Tidak ada bypass key Delta.

## Antrean, timeout, rename, dan keamanan

Command dikirim FIFO pada sync berikutnya. ACK berarti perintah sudah diproses,
**bukan berarti rejoin berurutan sudah selesai**. Setelah timeout default 90 detik,
balasan menjadi ⌛ tetapi **command tetap antre** dan berjalan ketika monitor online.
ACK terlambat mengedit balasan selama token masih berlaku (sekitar 15 menit).
Setelah itu hanya event hasil ringkas dicatat. Command sent tanpa ACK >60 detik
dikirim ulang sekali, kecuali restart/Launch All. Kontrak device tidak menjamin
exactly-once; efek rejoin command lain bisa terulang bila ACK hilang.

Rename memindahkan snapshot/antrean dan tetap menerima ACK batch lama berdasarkan
ID serta nama asal. Nama yang bentrok ditolak. Mengosongkan `webhook.deviceName`
mengembalikan nama model yang ditentukan device: nama barunya baru diketahui saat
sync berikutnya, sehingga entri lama bisa terlihat offline.

- Secret valid: **satu sync per empat detik per device**. ACK/upload tidak terkena
  limit sync. Banyak device boleh berbagi IP Redfinger/NAT.
- Auth gagal: **60 request/menit per IP**, berikutnya `429`. Bucket auth gagal tidak
  memblokir request dengan secret valid.
- Di Render, IP berasal dari entri paling kanan `X-Forwarded-For` yang ditambahkan
  proxy Render; lokal memakai socket IP. Jangan set `RENDER=true` tanpa proxy tepercaya.
- Log tidak mencakup body sync, private-server link, webhook URL, script, secret,
  token interaction, atau screenshot. Screenshot tidak disimpan di disk.

## Lokal dan registrasi manual

```sh
cd bot
npm ci
cp .env.example .env
# Isi .env; jangan commit secret.
node --env-file=.env src/index.js
# Daftar ulang manual:
node --env-file=.env scripts/register.js
# Bila env sudah di-export oleh shell/hosting:
npm start
npm run register
```

PUT registrasi mengganti seluruh command aplikasi dalam guild tersebut. Gunakan
aplikasi Discord khusus bot ini agar command aplikasi lain tidak tertimpa.

Tanpa `DATA_DIR`, restart/redeploy menghapus state; snapshot pulih saat sync berikutnya,
command yang belum selesai perlu diulang. Hosting dengan disk persisten dapat memakai
`DATA_DIR` privat (contoh lokal `./state`). JSON ditulis atomik dengan debounce dua
detik dan di-flush saat shutdown. Snapshot/args dapat mengandung link pribadi,
script, atau setting webhook: jaga izin folder. Token tidak dipersist, jadi command
hasil restore tidak bisa mengedit interaction lama. Screenshot yang sudah ACK dan
hanya menunggu upload tidak dipersist.

`node_modules/`, `.env`/varian lokal, `state.json`/temp, dan folder state lokal standar
di-ignore. Jika lokasi `DATA_DIR` berbeda di dalam checkout, tambahkan lokasi itu
ke ignore lokal; untuk hosting disarankan folder di luar checkout.

## Tes dan troubleshooting

```sh
cd bot
npm ci
npm test
```

Tes menggunakan HTTP localhost, mock Discord dan waktu terkontrol. Ini tidak
menghubungi Discord atau cloud phone asli. Mock sync (isi env URL/SECRET di terminal):

```sh
curl -s -X POST "$URL/api/sync" -H "Authorization: Bearer $SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"protocol":1,"device":"TEST","version":"x","time":0,"presets":{},"instances":[],"settings":[]}'
# Refresh /status di Discord; sync ulang setelah >=4 detik untuk mengambil command.
curl -s -X POST "$URL/api/ack" -H "Authorization: Bearer $SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"protocol":1,"device":"TEST","id":"<id-command>","ok":true,"message":"tes"}'
```

- Slash command hilang: cocokkan APP_ID/GUILD_ID, scope invite, dan log startup;
  jalankan registrasi manual. Kosongkan Interactions Endpoint URL.
- `401`: secret/Bearer salah. `429`: sync terlalu cepat atau terlalu banyak auth
  gagal. Request valid tetap diterima walau IP terkena limit auth gagal.
- Device offline/⌛: cek URL, internet, secret, dan monitor. Jangan mengulang command
  berkali-kali karena command timeout masih antre.
- File/balasan gagal: cek permission Attach Files/Embed Links, batas ukuran dan umur
  token. Edit Discord yang gagal dicoba kembali selama token aktif.
- Redeploy: tunggu snapshot berikutnya. Node/npm tidak diperlukan di device. Folder
  `bot/` ikut checkout auto-update tetapi engine tidak menjalankannya.
- Verifikasi nyata: `/preset set`, `/game`, `/default`, `/restart`, `/screenshot`,
  `/script add` dan `/autoexec add/remove`. Cek device:
  `grep -E 'Remote:|launching|in game' ~/rejoin/data/rejoin.log | tail -40`.
  Hasil simulasi tidak berarti sudah dites pada Discord/Render/device asli.
