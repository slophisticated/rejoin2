# PRD — Rejoin Control Bot (Discord)

**Tambahan diagnostik branch `trial/no-login-autojoin`:** slash command
`/clone test-close device:...` (satu device, tidak mendukung all) memakai konfirmasi
**Tutup Clone4**, lalu mengirim `{type:"test_close",args:{}}`. Target tetap package
`com.apengjers.v6`, wajib tepat satu pada snapshot dan konfigurasi device. Handler
memerlukan konteks monitor, antrean loading/rejoin kosong, proses hidup, serta login
terverifikasi. Selector clone ditolak. Hanya memanggil force-stop target; tidak
menghapus cookie, mencabut sesi, atau mengubah service. Recovery monitor tetap
berjalan. Ini tes pembeda terhadap logout bot, bukan fix FC; tetap berisiko
mengganggu jendela clone lain. Deploy bot branch ini dan registrasi ulang slash
command diperlukan selain update device.

Dokumen ini buat agent / developer yang akan **membangun bot Discord** untuk mengontrol
Rejoin. Sisi Rejoin (device) **sudah jadi** (`managers/remote.lua`). Bot harus
mengikuti kontrak di dokumen ini persis. Baca juga `AGENTS.md` untuk konteks project.

---

## 1. Latar belakang & tujuan

Rejoin = engine Lua di Termux (cloud phone Redfinger, root) yang membuka dan menjaga
banyak clone Roblox. Pemilik (joki) menjalankan **beberapa device**, masing-masing
dengan beberapa clone, dan sering **ganti game** (mis. 2 game: Grow a Garden dan
Fisch). Sekarang semua setting diubah lewat menu Termux di tiap device, satu-satu.

**Tujuan:** semua yang butuh config bisa diatur dari Discord lewat **slash command**
dengan balasan **ephemeral** (cuma pemilik yang lihat, channel tidak spam):
- preset game & pindah game (semua clone / sebagian / satu)
- daftar clone (tambah / ubah / hapus, link, preset)
- restart satu clone, Launch All
- Discord webhook status (URL, interval, screenshot, sembunyikan nama),
  nama device, **ganti device** (lanjutkan pesan status lama)
- jendela floating, heartbeat & mode hemat, jeda launch, dll (semua setting di §6)
- **screenshot** layar cloud phone saat itu juga (balasan ephemeral)
- rejoin **beberapa clone sekaligus** (pilih banyak clone)
- **script Delta**: upload/tambah script ke folder Scripts, hapus, lihat; masukkan /
  keluarkan dari Autoexecute (copy dari Scripts, per device)
- lihat status semua device

**Bukan tujuan (v1):** login akun / inject cookie, ambil key Delta (dilarang — jangan
buat bypass key system), upload file bebas ke device (APK / file apa pun selain script
`.lua`/`.txt` ≤200 KB lewat `/script add`, yang **termasuk v1**), kontrol non-owner.

## 2. Arsitektur

```
 Discord  <--gateway-->  BOT (Render, Node)   <--HTTPS polling--  Device (Rejoin di Termux)
   slash command              antrian command per device          POST /api/sync tiap ±30 dtk
   balasan ephemeral          snapshot terakhir per device        POST /api/ack per command
```

- Cloud phone **tidak punya IP publik** → device yang menghubungi bot. Bot **tidak
  pernah** menghubungi device.
- Device mengirim **snapshot lengkap** tiap sync (preset, clone, setting). Bot cukup
  menyimpan snapshot terakhir; kalau state bot hilang (redeploy), sync berikutnya
  mengisinya lagi.
- Perintah dari Discord **diantrikan** per device, diambil device di sync berikutnya
  (jeda ≤ interval device, default 30 dtk), lalu hasilnya dikirim lewat `/api/ack`
  dan bot **mengedit balasan ephemeral**.

## 3. Stack & deploy

- Implementasi bot: Node.js 24, `discord.js` v14, server HTTP pakai `node:http` (tanpa framework, tanpa
  database). Satu proses: bot gateway + HTTP API pada `PORT`.
- Penyimpanan: **memori saja** (Render free tidak punya disk persisten). Opsional
  `DATA_DIR` → file JSON `state.json` (tulis atomik, debounce ±2 dtk) kalau nanti pindah
  ke hosting dengan disk. State hilang saat restart/redeploy itu **aman**: device
  mengirim ulang snapshot di sync berikutnya; yang hilang cuma antrian command yang
  belum diambil (user cukup ulang command).
- Slash command didaftarkan **otomatis saat bot start** (REST `PUT
  applications/{APP_ID}/guilds/{GUILD_ID}/commands`), jadi tidak perlu langkah manual.
  `scripts/register.js` tetap ada untuk daftar ulang manual.
- HTTP server **wajib listen di `process.env.PORT` pada `0.0.0.0`** (aturan Render).
- Kode bot ditaruh di folder **`bot/`** repo `slophisticated/rejoin2` (repo public →
  tidak boleh ada secret di kode; semua lewat env).
- Struktur yang disarankan:
  ```
  render.yaml              (di root repo) blueprint Render, lihat §3.1
  bot/
    package.json
    README.md              cara deploy + isi env + invite bot + register command
    src/index.js           start gateway + http
    src/http.js            /api/sync, /api/ack, /health
    src/store.js           state device, antrian, persist
    src/commands/*.js      definisi + handler slash command
    src/format.js          render balasan (embed / teks)
    scripts/register.js    daftarkan slash command (guild)
  ```

### Environment variable

| Nama | Wajib | Isi |
|---|---|---|
| `DISCORD_TOKEN` | ya | token bot |
| `APP_ID` | ya | application id |
| `GUILD_ID` | ya | server tempat command didaftarkan (guild command = langsung aktif) |
| `OWNER_IDS` | ya | user id Discord yang boleh pakai, dipisah koma |
| `DEVICE_SECRET` | ya* | string acak panjang (≥32 char), sama dengan `remote.secret` di device |
| `HWID_USERS` | tidak | ID Discord yang boleh `/hwid redeem` dengan akun sendiri (`u<id>`); `OWNER_IDS` juga boleh (akun bareng) |
| `HWID_CHANNEL_ID` | tidak | channel privat buat nyimpen daftar HWID (satu pesan per HWID: `rejoin-hwid v1 <sha256> <idOwner>`) kalau ga ada `DATA_DIR`. **Daftar HWID**: `/hwid redeem hwid:<hex>` mencatat sha256(`rejoin-hwid|<hwid>`) → idOwner (di `DATA_DIR/hwid.json` dan/atau channel); device tanpa secret sync dengan header `X-Rejoin-Hwid`, akun = akun idOwner. `/hwid remove` mencabut |
| `OWNERS` | tidak* | `idDiscord:secret,...` — device **terpisah per owner**: secret yang dipakai device menentukan akunnya; tiap owner hanya melihat/mengontrol device akunnya (nama device boleh sama antar akun). *Wajib `OWNERS` atau pasangan `OWNER_IDS`+`DEVICE_SECRET` (keduanya boleh dipakai bersamaan) |
| `PORT` | otomatis dari Render | port HTTP (jangan di-hardcode) |
| `DATA_DIR` | tidak | folder persist (kosong di Render free = memori saja) |
| `COMMAND_TIMEOUT_SEC` | tidak | default 90 |

### 3.1 Deploy di Render (free)

- Jenis: **Web Service**, runtime Node, plan **Free**, dari repo GitHub `rejoin2`,
  **Root Directory `bot`**, Build `npm ci`, Start `node src/index.js`,
  **Health Check Path `/health`**.
- **Build Filter**: hanya `bot/**`, supaya push perubahan rejoin (Lua) tidak me-restart
  bot.
- Sertakan `render.yaml` di root repo:
  ```yaml
  services:
    - type: web
      name: rejoin-bot
      runtime: node
      plan: free
      rootDir: bot
      buildCommand: npm ci
      startCommand: node src/index.js
      healthCheckPath: /health
      autoDeployTrigger: commit
      buildFilter:
        paths:
          - bot/**
      envVars:
        - key: DISCORD_TOKEN
          sync: false
        - key: APP_ID
          sync: false
        - key: GUILD_ID
          sync: false
        - key: OWNER_IDS
          sync: false
        - key: DEVICE_SECRET
          generateValue: true
  ```
- **Tidur di free tier**: Render free mematikan service setelah ±15 menit tanpa
  request HTTP masuk, dan **bot Discord ikut offline** (slash command gagal). Selama ada
  minimal 1 device yang monitornya jalan, sync tiap ±30 dtk menjaganya tetap bangun.
  README bot harus menyarankan monitor gratis (mis. UptimeRobot / cron-job.org) yang
  memanggil `GET /health` tiap 5 menit supaya bot tetap online walau semua device mati.
  Bangun dari tidur butuh ±1 menit; request pertama device boleh gagal (device akan
  mencoba lagi dengan jeda makin lama: x2 … x10 interval).
- Saat start: log `listening on :PORT` + `logged in as <bot tag>`; jangan log env.
- URL device = URL Render service (`https://<nama>.onrender.com`).

Bot tidak butuh privileged intent (pakai slash command, bukan baca pesan).

## 4. Kontrak HTTP (device ↔ bot)

Semua request: `POST`, `Content-Type: application/json`,
header `Authorization: Bearer <DEVICE_SECRET>`. Bandingkan secret dengan
`crypto.timingSafeEqual`. Salah/kosong → **401** `{"error":"unauthorized"}`.
Body maks **512 KB** (lebih → 413; isi script bisa sampai 200 KB). JSON rusak → 400. Field `protocol` saat ini `1`.

### 4.0 `POST /api/ping`

Tes koneksi dari Menu 9 → 11: body `{"protocol":1}`, dengan autentikasi yang sama
seperti sync (Bearer secret atau `X-Rejoin-Hwid` yang terdaftar). Respons sukses
`200 {"ok":true}`. Protocol/body tidak valid → 400; auth ditolak → 401.
Endpoint ini tidak memanggil sync/ACK, tidak mengambil command, dan tidak mengubah
snapshot, status online, atau waktu pembatas sync. Bot lama yang belum punya
endpoint membalas 404; device meminta update bot tanpa fallback ke `/api/sync`.

### 4.0b `POST /api/poll` (long poll)

Body `{"protocol":1,"device":"RF-07","wait":5}`, auth sama seperti sync. Bot menahan
request sampai ada command `queued` untuk device itu (balas langsung
`200 {"pending":true}`) atau sampai `wait` detik habis (maks 25, balas
`{"pending":false}`). Tidak membawa snapshot dan tidak mengambil command; hanya
memperbarui status online. Begitu `pending:true`, device langsung `/api/sync` (sync
ini tidak kena batas 4 detik selama masih ada command `queued`). Device memakai jeda
antar siklus monitor (dan jeda saat Launch All) sebagai long poll, jadi command jalan
±1–2 detik setelah dikirim. Bot lama → 404: device kembali ke sleep biasa (cek lagi
10 menit kemudian). Poll tidak dicatat di log bot.

### 4.1 `POST /api/sync`

Request (dikirim device tiap `remote.interval` detik, saat monitor jalan):
```json
{
  "protocol": 1,
  "device": "RF-07",
  "deviceId": "de66d5e6b3038d94",
  "version": "f6aac49",
  "time": 1760780000,
  "presets": { "A": { "name": "Steal an Egg", "link": "https://www.roblox.com/games/..." },
               "B": { "name": "Fisch", "link": "https://www.roblox.com/share?code=...&type=Server" } },
  "defaultPreset": "A",
  "instances": [
    { "id": 1, "name": "Clone1", "package": "com.apengjers.v3",
      "preset": "A", "slot": "kiri atas", "presetSource": "default", "game": "Steal an Egg",
      "link": "https://www.roblox.com/games/...", "status": "ingame",
      "username": "Fahmssz239", "fps": 15, "mem": 420 },
    { "id": 3, "name": "Clone3", "package": "com.apengjers.v5",
      "preset": "B", "presetSource": "khusus", "game": "Fisch",
      "link": "https://www.roblox.com/share?code=...", "status": "ingame" }
  ],
  "scripts": [ { "name": "egg_farm.lua", "size": 1520, "auto": true },
               { "name": "hub.lua", "size": 81, "auto": false } ],
  "autoexecute": [ { "name": "egg_farm.lua", "size": 1520, "fromScripts": true, "managed": false },
                   { "name": "rejoin_heartbeat.lua", "size": 5321, "fromScripts": false, "managed": true } ],
  "settings": [
    { "key": "launchJoinTimeout", "type": "int", "label": "Maks tunggu clone masuk game (dtk)",
      "min": 0, "max": 1800, "value": 240 },
    { "key": "webhook.url", "type": "string", "label": "URL Discord webhook", "max": 300,
      "secret": true, "value": "set" }
  ]
}
```
- `device` = nama device (diatur dari `device_rename`; default model HP). **Kunci
  identitas device** di bot. `deviceId` (hex acak, dibuat sekali per device di
  `data/device_id.txt`): kalau nama baru muncul dengan `deviceId` sama dan nama lama sudah
  diam ≥2× interval, entri lama digabung ke nama baru (antrian ikut pindah); dua device
  online dengan nama sama tapi `deviceId` beda ditandai ⚠️ di `/devices`. Kalau nama berubah, device lama otomatis jadi "offline"
  (tidak sync lagi) dan entri baru muncul — bot boleh menggabungkan kalau command
  `device_rename` yang menyebabkannya (lihat §5.4).
- **Preset default**: tiap clone ikut `defaultPreset`, kecuali punya preset sendiri.
  `presetSource` per clone: `default` (ikut default), `khusus` (preset sendiri),
  `link` (pakai link sendiri, preset `-`), `none` (belum ada link). `preset` = preset
  yang **benar-benar dipakai**, `game` = nama game, `link` = link yang dipakai join.
- `status` per clone: `ingame`, `starting`, `recovery`, `nologin`, `kicked`, `freeze`,
  `stuck`, `offline`, `unknown`.
- `username`, `fps`, `mem` opsional.
- `settings`: daftar setting yang **boleh** diubah (schema + nilai sekarang). Field
  `secret: true` → `value` hanya `"set"` atau `""` (nilai asli tidak pernah dikirim).
  Bot **harus** memakai daftar ini untuk opsi/autocomplete `/config`, bukan hardcode.
- `scripts` = isi **folder Scripts** Delta (gudang script); `auto: true` = ada copy-nya
  di Autoexecute. `autoexecute` = isi folder Autoexecute (`managed: true` = script
  heartbeat milik rejoin, jangan ditawarkan untuk dihapus). Folder Delta dipakai
  **bersama semua clone di device itu**, jadi script berlaku per device.

Response 200:
```json
{ "commands": [ { "id": "c_8f3a", "type": "game", "args": { "preset": "B", "clones": ["Clone2"] } } ] }
```
- Bot mengembalikan **semua** command antrian device itu (FIFO) dan menandainya
  `sent` (jangan dihapus sampai ack / timeout). Kalau sync berikutnya datang dan
  command `sent` belum di-ack > 60 dtk, kirim ulang sekali (device idempoten untuk
  setting; untuk `restart`/`launch_all` boleh tidak dikirim ulang).
- Antrian kosong → `{"commands":[]}`.
- Bot menyimpan snapshot + `lastSeen = now`.

### 4.2 `POST /api/ack`

```json
{ "protocol": 1, "device": "RF-07", "id": "c_8f3a", "ok": true,
  "message": "Clone2 → B (Fisch), rejoin berurutan", "data": null }
```
- `message` sudah berbahasa Indonesia, siap ditampilkan.
- `data` opsional (mis. command `status` mengirim snapshot lengkap). Device juga
  nempelin snapshot terbaru (`protocol: 1`) ke ACK command lain yang ga punya data
  sendiri (kecuali `screenshot`), jadi `/script list`, `/clone list`, `/overview`
  langsung ikut berubah. Bot nyimpen snapshot itu; snapshot rusak di ACK non-`status`
  dibuang tanpa nolak ACK-nya.
- Bot: cari command by `id` → hapus dari antrian → `editReply` interaction asal
  (ephemeral) dengan ✅/❌ + `message`. Response `{"ok":true}`. Id tidak dikenal → 200
  juga (abaikan).

### 4.2b `POST /api/upload/<commandId>`

Dipakai command `screenshot`: device mengunggah gambar **sebelum** mengirim ack.
- Auth sama (`Bearer`), `Content-Type: image/png`, body = file PNG mentah (bukan
  multipart), maks **8 MB** (lebih → 413). `<commandId>` = id command yang ada di antrian
  dan bertipe `screenshot`; id lain → 404.
- Bot simpan buffer di memori (hapus setelah dikirim ke Discord atau 5 menit).
- Saat ack `ok:true` dengan `data.uploaded:true` datang → `editReply({ content, files:
  [{ attachment: buffer, name: "screenshot-<device>.png" }] })`. Tangani juga urutan
  terbalik (ack dulu, upload belakangan): tunggu upload maks 30 dtk.
- Response `{"ok":true}`.

### 4.3 `GET /health`
`200 {"ok":true,"devices":N}` tanpa auth (health check Render + monitor uptime). Harus
cepat (tanpa memanggil Discord). Jangan bocorkan nama device / data lain.

### 4.4 URL dari repo + pindah URL (ganti hosting / service baru)
Device yang `remote.secret`-nya diisi tapi `remote.url` kosong mengambil URL dari file
yang sama (maks sekali per 10 menit), jadi tiap device cukup diisi secret.
Device yang gagal sync 5x berturut-turut juga membaca
`https://raw.githubusercontent.com/slophisticated/rejoin2/main/remote_url.txt`
(URL https pertama di file itu) dan pindah sendiri. README bot harus menjelaskan:
setelah deploy pertama / di akun/URL baru → edit `remote_url.txt` di repo `rejoin2` → push.
`DEVICE_SECRET` harus tetap sama.

## 5. Command yang dikenal device (`type` + `args`)

Device memvalidasi semuanya dan membalas `ok:false` + pesan kalau salah. Bot tetap
sebaiknya validasi ringan di depan (supaya error langsung, tanpa nunggu sync).
`clone` / `clones` boleh berisi **id angka, nama, atau package**.

| type | args | Efek di device |
|---|---|---|
| `status` | `{}` | Balas ringkasan + `data` = snapshot lengkap |
| `default_set` | `{preset, rejoin?: bool=true}` | Ganti preset **default**; clone yang ikut default di-rejoin berurutan |
| `game` | `{preset, clones?: [..] \| "all", rejoin?: bool=true}` | Tanpa `clones` / `"all"`: preset itu jadi default **dan semua clone ikut default** (preset khusus dilepas). Dengan `clones`: clone itu dapat preset **khusus**. Rejoin berurutan |
| `set_preset` | sama dengan `game` | alias |
| `restart` | `{clone}` atau `{clones:[..] \| "A,B"}` | Rejoin clone itu (berurutan). `clones` boleh array atau teks dipisah koma |
| `report` | `{}` | Report error Menu 4 (info device, login + heartbeat per clone, error/warn + aktivitas semua log; rahasia disensor) → ack `data:{name, content}`, bot lampirin sebagai file `.txt` |
| `screenshot` | `{}` | Device `screencap` layar penuh → `POST /api/upload/<id>` → ack `data:{uploaded:true, bytes}` |
| `launch_all` | `{}` | Rejoin semua (login duluan, satu per satu) |
| `preset_set` | `{key, name, link, rejoin?: bool}` | Tambah/ubah preset. `key` `^[A-Za-z0-9_]{1,16}$` (bukan `default`); `link` harus `https://*roblox.com/...` atau `roblox://...`. Preset pertama otomatis jadi default. `rejoin:true` → clone pemakai preset di-rejoin |
| `preset_remove` | `{key}` | Hapus preset (ditolak kalau itu default); clone yang khusus ke preset itu jadi ikut default |
| `instance_add` | `{name, package, preset?, link?}` | Tambah clone ke daftar (package `com.x.y`, unik). Tanpa `preset` = ikut default |
| `instance_edit` | `{clone, name?, package?, preset?, link?}` | Ubah clone. `preset`: kode = khusus, `""`/`"default"` = ikut default, `"-"` = pakai link sendiri (butuh `link` / link lama). `link:""`/`"-"` = hapus link sendiri |
| `instance_remove` | `{clone}` | Hapus dari daftar (app tidak di-uninstall) |
| `logout_alarm_set` | `{clone, date, time, daily?}` | Simpan alarm logout per clone pada tanggal + `HH:MM` WIB; `date` format `DD/MM` (kejadian mendatang terdekat) atau `DD/MM/YYYY`. Sekali atau berulang harian mulai tanggal itu. Dieksekusi lokal oleh monitor |
| `logout_alarm_remove` | `{clone}` | Hapus alarm logout clone |
| `delta_key_input` | `{key}` | Tulis key Delta yang **didapat user sendiri** ke file license Delta (yang terdeteksi, atau `<Delta>/Internals/Cache/license`; `.license` buatan Delta ga pernah disentuh), lalu rejoin semua clone lewat antrean. Ga ada ambil/bypass key. Transient kayak `cookie_inject`: ga dipersist, ga di-log, ga diretry, args dihapus setelah ACK / timeout |
| `cookie_inject` | `{clone, token}` | Verifikasi lalu inject cookie ke tepat satu clone; ditolak saat Launch All jalan. Command transient: token tidak dipersist ke state bot, tidak dicatat ke log, tidak diretry, dihapus setelah ACK atau timeout 90 detik |
| `logout` | `{clones:[id/nama]}` | Pada branch percobaan, permintaan masuk antrean slot: target lain menunggu loading selesai; target aktif mengakhiri wait lamanya. ACK berarti diantrekan, hasil akhir `[LOGOUT]` di log device. Target yang masih login ditutup, sesi Roblox dicoba di-revoke, cookie lokal dihapus dengan backup dan cache dilupakan. `all` ditolak |
| `config_set` | `{key, value}` | Ubah 1 setting dari daftar §6 (key lain ditolak) |
| `device_rename` | `{name}` | = `config_set webhook.deviceName` |
| `webhook_use_message` | `{link}` | Ganti device: lanjutkan pesan status lama (link pesan Discord atau ID) |
| `webhook_test` | `{}` | Kirim laporan status sekarang |
| `script_add` | `{name, content? \| url?}` | Simpan script ke **folder Scripts** (`name` `^[A-Za-z0-9_.-]+$` ≤64, `.lua` ditambah otomatis; `content` ≤200 KB; atau `url` https → dibuat 1 baris `loadstring(game:HttpGet(url))()`). Nama sama → diganti, dan copy di Autoexecute ikut diperbarui |
| `script_remove` | `{name}` | Hapus dari Scripts (copy di Autoexecute tidak disentuh; pesan memberi tahu) |
| `script_get` | `{name}` | `data = {name, content}` untuk `/script view` |
| `auto_add` | `{name, rejoin?: bool=false}` | **Copy** script dari Scripts ke Autoexecute (satu-satunya cara isi Autoexecute). `rejoin:true` → semua clone rejoin berurutan |
| `auto_remove` | `{name, rejoin?: bool=false}` | Hapus copy di Autoexecute (Scripts tetap). `rejoin_heartbeat.lua` ditolak |

> Aturan script: **tidak ada** command yang menulis isi script langsung ke Autoexecute.
> Isi masuk lewat `script_add` (Scripts), lalu `auto_add` menyalinnya.

Catatan perilaku:
- Rejoin selalu **berurutan** (clone login duluan, tunggu masuk game) supaya RAM tidak
  numpuk. Pesan ack keluar **sebelum** rejoin selesai (rejoin jalan di siklus monitor).
- Setelah menerima command apa pun, device **sync tiap 5 dtk selama 2 menit** (mode
  cepat), lalu kembali ke `remote.interval`. Jadi command lanjutan (mis. screenshot
  setelah restart) cepat dibalas. Rate limit bot harus mengizinkan ini (≥1 sync / 5 dtk).
- `clone` / `clones` di semua command boleh id, nama, atau package; `clones` boleh array
  atau teks dipisah koma (`"Clone1,Clone3"`).
- Command hanya diproses saat **monitor jalan** (Menu 1 Start Monitor / Menu 5 Launch All / boot). Kalau device tidak
  sync > 3× interval, bot menandai device **offline** dan tetap mengantrikan command
  (berlaku saat device online lagi) — beri tahu user di balasan.

### 5.4 Rename device
Setelah ack `device_rename` sukses, bot memindahkan antrian & snapshot dari nama lama
ke nama baru (sync berikutnya datang dengan nama baru).

## 6. Setting yang bisa diubah (`config_set`)

Daftar resmi dikirim device di `settings` (pakai itu). Saat ini:

| key | type | batas | arti |
|---|---|---|---|
| `launchJoinTimeout` | int | 0–1800 | maks tunggu clone masuk game (dtk) |
| `launchSettleDelay` | int | 0–600 | jeda kalau heartbeat tidak ada |
| `launchEmptyDelay` | int | 0–120 | jeda clone belum login |
| `launchWaitTimeout` | int | 5–600 | maks tunggu Roblox kebuka |
| `launchWaitInterval` | int | 1–60 | interval cek saat launch |
| `monitorInterval` | int | 2–120 | interval monitor |
| `freezeTimeout` | int | 30–7200 | batas freeze sebelum relaunch |
| `minRss` | int | 0–4000 | RSS minimal clone hidup (MB) |
| `relaunchNoLogin` | bool | | buka lagi clone belum login yang FC |
| `noLoginCooldown` | int | 30–3600 | jeda buka lagi clone belum login |
| `launchMinFreeMb` | int | 0–4000 | RAM bebas minimal sebelum buka link game (MB) |
| `launchFreeWait` | int | 0–300 | maks tunggu RAM bebas sebelum buka link (dtk) |
| `windowLayout.enabled` | bool | | auto atur jendela grid |
| `windowLayout.columns` | int | 0–10 | kolom (0 = otomatis) |
| `windowLayout.gap` | int | 0–200 | jarak jendela (px) |
| `windowLayout.overlap` | int | 0–400 | baris atas numpuk (px) |
| `heartbeat.enabled` | bool | | heartbeat Delta |
| `heartbeat.saver.enabled` | bool | | mode hemat |
| `heartbeat.saver.fpsCap` | int | 0–240 | batas FPS mode hemat |
| `heartbeat.saver.disable3d` | bool | | render 3D mati |
| `webhook.url` | string (secret) | pola `https://*/api/webhooks/...` atau "" | URL webhook status |
| `webhook.interval` | int | 60–3600 | interval laporan |
| `webhook.screenshot` | bool | | screenshot |
| `webhook.hideNames` | bool | | sembunyikan nama akun |
| `webhook.deviceName` | string | ≤60 | nama device |
| `deltaLicensePath` | string | ≤300 | path file license Delta ("" = otomatis) |
| `appAutoExecutePath` | string | ≤300 | folder Autoexecute Delta |
| `scriptsPath` | string | ≤300 | folder Scripts Delta ("" = otomatis di sebelah Autoexecute) |
| `remote.interval` | int | 10–600 | interval sync ke bot |

`value` dikirim sebagai string atau tipe aslinya; bool menerima `true/false/on/off/ya/tidak/1/0`.
`remote.url` dan `remote.secret` sengaja **tidak** bisa diubah dari bot.

## 7. Slash command

Semua: hanya `OWNER_IDS` (lainnya → ephemeral "❌ Kamu tidak punya akses."), **semua
balasan ephemeral**, nama command & teks **bahasa Indonesia santai**.
Opsi `device` di semua command: autocomplete dari device yang dikenal (+ `all` kalau
relevan). Kosong + cuma 1 device dikenal → otomatis device itu; >1 device → wajib
(balas error ephemeral). `clone`: autocomplete dari snapshot device terpilih
(tampilkan `nama — username — status`). `preset`: autocomplete key + nama.

| Command | Opsi | Command device |
|---|---|---|
| `/status` | `device?` | tampil dari snapshot (tanpa antri). Tombol "🔄 Refresh" → antri `status` |
| `/overview` | `device?` (kosong = semua device akun) | Lokal dari snapshot, tanpa command: per device versi rejoin (`version`; peringatan kalau beda-beda), clone (status, slot, username ikut `hideNames`, preset + sumber), daftar preset (⭐ default), Scripts (⚡ = di Autoexecute), Autoexecute (tanpa script milik rejoin) |
| `/devices` | – | daftar device: nama, versi, online/offline (lastSeen), jumlah clone ingame/total |
| `/game` | `preset`, `device?` (bisa `all`), `clones?`, `rejoin?` (default true) | tanpa `clones` → `game` (preset jadi default, semua clone ikut); dengan `clones` → `game` clones=[...] (khusus) |
| `/default` | `preset`, `device?` (bisa `all`), `rejoin?` | `default_set` (clone khusus tidak ikut pindah) |
| `/preset list` | `device?` | dari snapshot |
| `/preset set` | `key`, `name`, `link`, `device?`(+`all`), `rejoin?` | `preset_set` |
| `/preset remove` | `key`, `device?`(+`all`) | `preset_remove` |
| `/clone list` | `device?` | dari snapshot |
| `/clone add` | `name`, `package`, `preset?`, `link?`, `device?` | `instance_add` |
| `/clone edit` | `clone`, `name?`, `package?`, `preset?`, `link?`, `device?` | `instance_edit` |
| `/clone remove` | `clone`, `device?` | `instance_remove` (pakai tombol konfirmasi dulu) |
| `/alarm set` | `device`, `clone`, `date` (`DD/MM` atau `DD/MM/YYYY`), `time` (`HH:MM` WIB), `daily?` | `logout_alarm_set`; tanggal tanpa tahun memilih kejadian berikutnya, `daily` default false |
| `/alarm list` | `device?` | Dari snapshot per clone (`logoutAlarm`) |
| `/alarm remove` | `device`, `clone` | `logout_alarm_remove` |
| `/alarm import` | `file` (CSV ≤200 KB, ≤100 baris; tanpa opsi device) | Kolom `DEVICE` (nama/label device), `USN` (username clone di snapshot), `TANGGAL` (`DD/MM[/YYYY]` atau `20-Oct`), `JAM` (`HH:MM` WIB), opsional `DAILY`, `NOTES`, `ORDER ID`, `Delete` (dicentang = dilewati). Preview ephemeral + CSV hasil cek; tombol Terapkan cek ulang snapshot (USN/alarm berubah = ditolak) lalu kirim `logout_alarm_set` per baris. Baris dobel untuk clone yang sama ditolak |
| `/delta input-key` | `device` | Modal ephemeral minta key Delta, lalu `delta_key_input`; device harus online |
| `/cookie inject` | `device`, `clone` | Modal ephemeral meminta cookie, lalu `cookie_inject`; satu clone, device harus online |
| `/clone logout` | `device`, `clones` (tanpa `all`) | `logout` (pakai tombol konfirmasi dulu) |
| `/restart` | `clones` (atau `all`), `device?` | `restart` clones=[...] / `launch_all` |
| `/report` | `device?` (bisa `all`) | `report` → file report error dari device (1 file per device untuk `all`) (sama kayak Menu 4, rahasia disensor) |
| `/screenshot` | `device?` (bisa `all`) | `screenshot` → gambar layar cloud phone di balasan ephemeral (≤10 gambar per balasan untuk `all`; lebih → follow-up ephemeral) |

**Opsi `clones` (pilih banyak clone):** opsi teks dengan autocomplete yang mendukung
banyak nilai dipisah koma — autocomplete menyarankan clone untuk bagian setelah koma
terakhir (mis. user ketik `Clone1, Cl` → saran `Clone1, Clone2`, `Clone1, Clone3`).
Bot memecah ke array sebelum dikirim. Alternatif yang juga boleh: setelah command,
tampilkan **select menu multi-pilih** (ephemeral, `min_values 1`, `max_values` = jumlah
clone) berisi clone dari snapshot.
| `/config get` | `device?`, `key?` | dari snapshot (`settings`), secret tampil "diset"/"kosong" |
| `/config set` | `key` (autocomplete dari `settings`), `value`, `device?`(+`all`) | `config_set` |
| `/webhook set` | `url`, `device?`(+`all`) | `config_set webhook.url` |
| `/webhook options` | `interval?`, `screenshot?`, `hide_names?`, `device?`(+`all`) | beberapa `config_set` |
| `/webhook test` | `device?` | `webhook_test` |
| `/device rename` | `name`, `device?` | `device_rename` |
| `/device remove` | `device` (wajib) | Lokal di bot (ga ada command ke device): hapus device yang **offline** dari daftar akun pemanggil setelah konfirmasi. Command pending device itu diselesaikan gagal ("Device dihapus dari bot."). Device online ditolak. Device yang sync lagi otomatis muncul lagi |
| `/device replace` | `message_link`, `device` | `webhook_use_message` — dipakai setelah ganti/replace cloud phone: pesan status device lama dilanjutkan oleh device baru |
| `/window` | `enabled?`, `columns?`, `gap?`, `overlap?`, `device?`(+`all`) | `config_set windowLayout.*` |
| `/saver` | `heartbeat?`, `enabled?`, `fps_cap?`, `disable3d?`, `device?`(+`all`) | `config_set heartbeat.*` |
| `/launch` | `join_timeout?`, `settle?`, `empty?`, `device?`(+`all`) | `config_set launch*` |
| `/script list` | `device?` | dari snapshot: daftar Scripts (tanda ⚡ kalau ada di Autoexecute) + daftar Autoexecute |
| `/script add` | `name`, `file?` (attachment `.lua`/`.txt`), `url?`, `code?` (teks pendek), `device?`(+`all`) | `script_add`. Salah satu dari `file`/`url`/`code` wajib. Bot **mengunduh attachment** (tolak >200 KB / bukan teks) dan mengirim isinya sebagai `content` |
| `/script view` | `name` (autocomplete dari `scripts`), `device?` | `script_get` → balas ephemeral dengan **file** `<name>` (attachment), bukan teks panjang |
| `/script remove` | `name`, `device?`(+`all`) | `script_remove` (tombol konfirmasi dulu) |
| `/autoexec list` | `device?` | dari snapshot `autoexecute` |
| `/autoexec add` | `name` (autocomplete dari `scripts` yang `auto:false`), `rejoin?`, `device?`(+`all`) | `auto_add` |
| `/autoexec remove` | `name` (autocomplete dari `autoexecute` yang `managed:false`), `rejoin?`, `device?`(+`all`) | `auto_remove` |

Catatan script: semua per device (berlaku ke **semua clone** di device itu). Tidak ada
opsi untuk menulis langsung ke Autoexecute — `/autoexec add` hanya menyalin dari Scripts.

Command dengan beberapa opsi → beberapa command device; balasan menunggu semuanya dan
menampilkan hasil per item.

### Alur balasan
1. `interaction.deferReply({ ephemeral: true })` (≤3 dtk).
2. Validasi ringan (preset ada di snapshot, key ada di `settings`, link pola benar).
   Gagal → `editReply("❌ ...")`.
3. Buat command `{id: "c_" + random, type, args}` → antri ke device (atau semua device
   untuk `all`). Simpan `{interaction token, createdAt}` per command.
4. `editReply("⏳ Dikirim ke RF-07, nunggu device (sync tiap ±30 dtk)…")`.
5. Saat ack: `editReply("✅ RF-07: Clone2 → B (Fisch), rejoin berurutan")` (❌ kalau
   `ok:false`). Banyak device → satu baris per device, update tiap ack masuk.
6. Tidak ada ack dalam `COMMAND_TIMEOUT_SEC` (90) → `editReply("⌛ RF-07 belum merespons
   (device offline / monitor tidak jalan). Command tetap antri.")`. Token interaction
   berlaku 15 menit; setelah itu ack hanya dicatat di log bot.

### Tampilan `/status`
Embed per device: judul `📊 RF-07 — v f6aac49 — online (12 dtk lalu)`, baris
`Default: [A] Steal an Egg`, lalu **per clone**:
```
🟢 Clone1 · ||Fahmssz239|| · 15fps 420MB
   [A] Steal an Egg (ikut default) · link: <https://www.roblox.com/games/...>
🟢 Clone3 · ||jivo9635||
   [B] Fisch (khusus) · link: <https://www.roblox.com/share?code=...>
```
Link dibungkus `<...>` biar Discord tidak bikin preview. Kalau lebih dari batas embed,
pecah per halaman (tombol ◀ ▶). Ikon status sama dengan
webhook rejoin: ingame 🟢, starting/recovery 🟡, nologin ⚪, kicked/freeze/stuck/offline 🔴.
Username tampil sebagai spoiler `||nama||` (ikuti `webhook.hideNames` dari settings).

## 8. Keamanan

- Hanya `OWNER_IDS`. Cek di setiap interaction (termasuk autocomplete & tombol).
- `DEVICE_SECRET` dibandingkan timing-safe; jangan pernah di-log / ditampilkan.
- Rate limit API untuk secret valid: maks 1 sync / 4 dtk per device (lebih → 429;
  mode cepat sync tiap 5 dtk). ACK dan upload valid tidak memakai pembatas sync.
  Batas 60 request/menit per IP **hanya menghitung request gagal auth** (secret salah /
  Bearer kosong); kegagalan berikutnya → 429. Request dengan secret valid tetap
  diterima meskipun IP terkena pembatas auth gagal, supaya banyak device Redfinger
  yang berbagi IP tidak saling memblokir. Upload maks 8 MB, hanya untuk id command
  `screenshot` yang sedang menunggu.
- Screenshot berisi layar semua clone (termasuk username) → hanya dikirim ephemeral ke
  owner, tidak disimpan di disk, tidak di-log.
- Jangan log **isi script** (command `script_add`, ack `script_get`).
- Jangan log body sync (berisi link private server). Log cukup: device, jumlah
  command, kode status.
- Link webhook (`/webhook set`) jangan diulang di balasan; tampilkan "diset".
- Validasi panjang string (nama ≤40, nama preset ≤60, link ≤300).
- Tidak ada fitur ambil / bypass key Delta.

## 9. Kriteria terima

1. Deploy di Render (§3.1) dengan env §3, `/health` 200, bot online di Discord, slash
   command muncul di server `GUILD_ID` tanpa langkah manual.
2. Device dengan `remote.url` + `remote.secret` muncul di `/devices` ≤ 1 menit setelah
   monitor jalan; secret salah → device tidak muncul, bot log 401 (tanpa secret).
3. `/preset set key:A …` lalu `/game preset:A` → ack ✅ di balasan ephemeral, device
   rejoin clone berurutan, `/status` menampilkan `[A] … (ikut default)` + link per clone.
   `/game preset:B clone:Clone3` → hanya Clone3 pindah (khusus); `/default preset:A`
   tidak memindahkan Clone3.
4. `/config set key:webhook.interval value:600` → ✅; `value:5` → ❌ dengan pesan batas
   dari device.
5. `/device replace` dengan link pesan status lama → ✅, laporan webhook berikutnya
   mengedit pesan itu.
6. Command ke device offline → balasan ⌛ setelah 90 dtk, dijalankan saat device online.
7. User di luar `OWNER_IDS` tidak bisa memakai command apa pun (termasuk autocomplete).
8. Redeploy bot (state hilang) → `/status` kembali normal setelah sync berikutnya.
9. Semua balasan ephemeral; channel tidak berisi pesan bot.
11. `/screenshot` → ≤ ±15 dtk (kalau device sedang mode cepat) atau ≤ interval + 15 dtk,
    gambar layar muncul di balasan ephemeral. `/restart clones:"Clone1,Clone3"` →
    hanya dua clone itu yang rejoin.

10. `/script add name:egg file:egg.lua` → muncul di `/script list`; `/autoexec add
    name:egg rejoin:true` → ✅, `/autoexec list` berisi `egg.lua`; `/script add` lagi
    dengan isi baru → copy di Autoexecute ikut berubah; `/autoexec remove` tidak
    menghapus dari Scripts; `rejoin_heartbeat.lua` tidak bisa dihapus.

## 10. Skenario tes tanpa device

Mock device dengan curl:
```sh
curl -s -X POST "$URL/api/sync" -H "Authorization: Bearer $SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"protocol":1,"device":"TEST","version":"x","time":0,"presets":{},"instances":[],"settings":[]}'
# -> {"commands":[...]} ; lalu kirim ack:
curl -s -X POST "$URL/api/ack" -H "Authorization: Bearer $SECRET" \
  -H 'Content-Type: application/json' \
  -d '{"protocol":1,"device":"TEST","id":"<id>","ok":true,"message":"tes"}'
```

## 11. Referensi di repo rejoin2

- Klien device: `managers/remote.lua` (schema setting, handler command, format sync/ack).
- Preset: `core/preset_cli.lua`, `managers/instance.lua` (`presetOf`, `gameLink`,
  `migrateToPresets`).
- Antrian rejoin: `managers/monitor.lua` (`Monitor.requestRejoin`, `runRejoinQueue`).
- Webhook status & nama device: `managers/webhook.lua`.
