# PRD — Rejoin Control Bot (Discord)

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
- Discord webhook status (URL, interval, screenshot, notif key, sembunyikan nama),
  nama device, **ganti device** (lanjutkan pesan status lama)
- jendela floating, heartbeat & mode hemat, jeda launch, dll (semua setting di §6)
- lihat status semua device

**Bukan tujuan (v1):** login akun / inject cookie, ambil key Delta (dilarang — jangan
buat bypass key system), upload file, kontrol non-owner.

## 2. Arsitektur

```
 Discord  <--gateway-->  BOT (Railway, Node)  <--HTTPS polling--  Device (Rejoin di Termux)
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

- Node.js 20+, `discord.js` v14, server HTTP pakai `node:http` (tanpa framework, tanpa
  database). Satu proses: bot gateway + HTTP API pada `PORT`.
- Penyimpanan: memori + file JSON `DATA_DIR/state.json` (tulis atomik: tulis temp lalu
  rename; debounce ±2 dtk). Kalau `DATA_DIR` tidak ada / tidak bisa ditulis → jalan
  memori saja (aman, karena device mengirim ulang snapshot).
- Deploy **Railway**: `package.json` dengan `"start": "node src/index.js"`, opsional
  Railway Volume ke `DATA_DIR`. URL publik Railway (https) dipakai device.
- Struktur yang disarankan:
  ```
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
| `DEVICE_SECRET` | ya | string acak panjang (≥32 char), sama dengan `remote.secret` di device |
| `PORT` | dari Railway | port HTTP |
| `DATA_DIR` | tidak | folder persist (`/data` kalau pakai volume) |
| `COMMAND_TIMEOUT_SEC` | tidak | default 90 |

Bot tidak butuh privileged intent (pakai slash command, bukan baca pesan).

## 4. Kontrak HTTP (device ↔ bot)

Semua request: `POST`, `Content-Type: application/json`,
header `Authorization: Bearer <DEVICE_SECRET>`. Bandingkan secret dengan
`crypto.timingSafeEqual`. Salah/kosong → **401** `{"error":"unauthorized"}`.
Body maks **256 KB** (lebih → 413). JSON rusak → 400. Field `protocol` saat ini `1`.

### 4.1 `POST /api/sync`

Request (dikirim device tiap `remote.interval` detik, saat monitor jalan):
```json
{
  "protocol": 1,
  "device": "RF-07",
  "version": "f6aac49",
  "time": 1760780000,
  "presets": { "A": { "name": "Steal an Egg", "link": "https://www.roblox.com/games/..." },
               "B": { "name": "Fisch", "link": "https://www.roblox.com/share?code=...&type=Server" } },
  "defaultPreset": "A",
  "instances": [
    { "id": 1, "name": "Clone1", "package": "com.apengjers.v3",
      "preset": "A", "presetSource": "default", "game": "Steal an Egg",
      "link": "https://www.roblox.com/games/...", "status": "ingame",
      "username": "Fahmssz239", "fps": 15, "mem": 420 },
    { "id": 3, "name": "Clone3", "package": "com.apengjers.v5",
      "preset": "B", "presetSource": "khusus", "game": "Fisch",
      "link": "https://www.roblox.com/share?code=...", "status": "ingame" }
  ],
  "settings": [
    { "key": "launchJoinTimeout", "type": "int", "label": "Maks tunggu clone masuk game (dtk)",
      "min": 0, "max": 1800, "value": 240 },
    { "key": "webhook.url", "type": "string", "label": "URL Discord webhook", "max": 300,
      "secret": true, "value": "set" }
  ]
}
```
- `device` = nama device (diatur dari `device_rename`; default model HP). **Kunci
  identitas device** di bot. Kalau nama berubah, device lama otomatis jadi "offline"
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
- `data` opsional (mis. command `status` mengirim snapshot lengkap).
- Bot: cari command by `id` → hapus dari antrian → `editReply` interaction asal
  (ephemeral) dengan ✅/❌ + `message`. Response `{"ok":true}`. Id tidak dikenal → 200
  juga (abaikan).

### 4.3 `GET /health`
`200 {"ok":true,"devices":N}` tanpa auth (untuk Railway health check). Jangan bocorkan
nama device / data lain.

### 4.4 Pindah URL (ganti akun Railway)
Device yang gagal sync 5x berturut-turut membaca
`https://raw.githubusercontent.com/slophisticated/rejoin2/main/remote_url.txt`
(URL https pertama di file itu) dan pindah sendiri. README bot harus menjelaskan:
setelah deploy di akun/URL baru → edit `remote_url.txt` di repo `rejoin2` → push.
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
| `restart` | `{clone}` atau `{clones:[..]}` | Rejoin clone itu (berurutan) |
| `launch_all` | `{}` | Rejoin semua (login duluan, satu per satu) |
| `preset_set` | `{key, name, link, rejoin?: bool}` | Tambah/ubah preset. `key` `^[A-Za-z0-9_]{1,16}$` (bukan `default`); `link` harus `https://*roblox.com/...` atau `roblox://...`. Preset pertama otomatis jadi default. `rejoin:true` → clone pemakai preset di-rejoin |
| `preset_remove` | `{key}` | Hapus preset (ditolak kalau itu default); clone yang khusus ke preset itu jadi ikut default |
| `instance_add` | `{name, package, preset?, link?}` | Tambah clone ke daftar (package `com.x.y`, unik). Tanpa `preset` = ikut default |
| `instance_edit` | `{clone, name?, package?, preset?, link?}` | Ubah clone. `preset`: kode = khusus, `""`/`"default"` = ikut default, `"-"` = pakai link sendiri (butuh `link` / link lama). `link:""`/`"-"` = hapus link sendiri |
| `instance_remove` | `{clone}` | Hapus dari daftar (app tidak di-uninstall) |
| `config_set` | `{key, value}` | Ubah 1 setting dari daftar §6 (key lain ditolak) |
| `device_rename` | `{name}` | = `config_set webhook.deviceName` |
| `webhook_use_message` | `{link}` | Ganti device: lanjutkan pesan status lama (link pesan Discord atau ID) |
| `webhook_test` | `{}` | Kirim laporan status sekarang |

Catatan perilaku:
- Rejoin selalu **berurutan** (clone login duluan, tunggu masuk game) supaya RAM tidak
  numpuk. Pesan ack keluar **sebelum** rejoin selesai (rejoin jalan di siklus monitor).
- Command hanya diproses saat **monitor jalan** (Menu 1 / boot). Kalau device tidak
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
| `webhook.events` | bool | | notif Delta minta key |
| `webhook.hideNames` | bool | | sembunyikan nama akun |
| `webhook.deviceName` | string | ≤60 | nama device |
| `deltaLicensePath` | string | ≤300 | path file license Delta ("" = otomatis) |
| `appAutoExecutePath` | string | ≤300 | folder Autoexecute Delta |
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
| `/devices` | – | daftar device: nama, versi, online/offline (lastSeen), jumlah clone ingame/total |
| `/game` | `preset`, `device?` (bisa `all`), `clone?`, `rejoin?` (default true) | tanpa `clone` → `game` (preset jadi default, semua clone ikut); dengan `clone` → `game` clones=[clone] (khusus) |
| `/default` | `preset`, `device?` (bisa `all`), `rejoin?` | `default_set` (clone khusus tidak ikut pindah) |
| `/preset list` | `device?` | dari snapshot |
| `/preset set` | `key`, `name`, `link`, `device?`(+`all`), `rejoin?` | `preset_set` |
| `/preset remove` | `key`, `device?`(+`all`) | `preset_remove` |
| `/clone list` | `device?` | dari snapshot |
| `/clone add` | `name`, `package`, `preset?`, `link?`, `device?` | `instance_add` |
| `/clone edit` | `clone`, `name?`, `package?`, `preset?`, `link?`, `device?` | `instance_edit` |
| `/clone remove` | `clone`, `device?` | `instance_remove` (pakai tombol konfirmasi dulu) |
| `/restart` | `clone` (atau `all`), `device?` | `restart` / `launch_all` |
| `/config get` | `device?`, `key?` | dari snapshot (`settings`), secret tampil "diset"/"kosong" |
| `/config set` | `key` (autocomplete dari `settings`), `value`, `device?`(+`all`) | `config_set` |
| `/webhook set` | `url`, `device?`(+`all`) | `config_set webhook.url` |
| `/webhook options` | `interval?`, `screenshot?`, `notif_key?`, `hide_names?`, `device?`(+`all`) | beberapa `config_set` |
| `/webhook test` | `device?` | `webhook_test` |
| `/device rename` | `name`, `device?` | `device_rename` |
| `/device replace` | `message_link`, `device` | `webhook_use_message` — dipakai setelah ganti/replace cloud phone: pesan status device lama dilanjutkan oleh device baru |
| `/window` | `enabled?`, `columns?`, `gap?`, `overlap?`, `device?`(+`all`) | `config_set windowLayout.*` |
| `/saver` | `heartbeat?`, `enabled?`, `fps_cap?`, `disable3d?`, `device?`(+`all`) | `config_set heartbeat.*` |
| `/launch` | `join_timeout?`, `settle?`, `empty?`, `device?`(+`all`) | `config_set launch*` |

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
- Rate limit API: maks 1 sync / 5 dtk per device (lebih → 429), 60 request/menit per IP.
- Jangan log body sync (berisi link private server). Log cukup: device, jumlah
  command, kode status.
- Link webhook (`/webhook set`) jangan diulang di balasan; tampilkan "diset".
- Validasi panjang string (nama ≤40, nama preset ≤60, link ≤300).
- Tidak ada fitur ambil / bypass key Delta.

## 9. Kriteria terima

1. Deploy di Railway dengan env §3, `/health` 200.
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
