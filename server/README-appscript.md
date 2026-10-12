# Server Key System (Google Apps Script)

Backend gratis untuk sistem key Rejoin (skala prive, <50 user). Tanpa install CLI,
tanpa biaya, tanpa domain sendiri.

## Arsitektur

```
Device (Termux)                   Google Apps Script Web App
  main.lua                        doPost
   ├─ POST /exec  {register}  ──►  cek key + kuota device, catat binding
   └─ POST /exec  {validate}  ──►  cek HMAC session + bukan revoked
        data/license.json (cache di device; permanen)
Sess token = deviceId + "." + HMAC_SHA256(secret, deviceId)
```

- **Key** = kode keluarga dengan kuota device (`maxDevices`).
- **Session permanen** — tidak kedaluwarsa; dicabut hanya oleh admin.
- Alur "gratis tapi anti-abuse": 1 kode tidak bisa dipakai device tak terbatas;
  validasi pakai HMAC (tanpa `HMAC_SECRET` tidak bisa forge session).

## Deploy (sekali)

1. Buka https://script.google.com → **New project**.
2. Tempel seluruh isi **`appscript.gs`** ke editor.
3. **Script Properties** — `Extensions > App Script Editor > Project Settings > Script Properties`:
   - `HMAC_SECRET` = string acak panjang (contoh: 32+ char). Inilah rahasia forge-proofing;
     jangan share, jangan taruh di repo/public.
4. **Deploy > New deployment**:
   - Type: **Web app**
   - Description: `rejoin-license`
   - **Execute as: Me**
   - **Who has access: Anyone**
5. Salin **Web app URL** (berakhiran `/exec`) → isi ke `config/config.lua`:
   ```
   license = {
       enabled = true,
       serverUrl = "https://script.google.com/macros/s/<ID>/exec",
   }
   ```

## Admin (dari EDITOR Apps Script)

Di editor, jalankan fungsi (trials: pilih fungsi di toolbar lalu Run):

| Fungsi | Kegunaan |
| --- | --- |
| `createKey("KODE123", 3, "note")` | buat key, maksimum 3 device terikat |
| `listKeys()` | daftar semua key + device + status revoked |
| `revokeDevice("deviceIdHex")` | cabut satu device (bisa re-register kalau slot kosong) |
| `revokeKey("KODE123")` | cabut SEMUA device key itu (paling ampuh) |
| `wipeAll()` | reset total database key/binding |

Log admin tampil di `Executions` (View > Executions).

## Catatan keamanan (jujur — skala prive)

- Anti-bypass level ini cuma sekedar gating: user iseng yang membaca kode bisa
  memalsukan respons HTTP atau menghapus gerbang. Di skala <50 user yang Anda
  kenal, ini dianggap cukup. Bila nanti publik, naikkan ke: HWID server-side yang
  lebih ketat + gate di kode native/obfuscated + rate limiting + endpoint admin
  terproteksi.
- `register` idempoten: device yang sudah terikat mengembalikan session lama.
- Quota kasus buruk: Apps Script Web App gratis ~90 eksekusi/menit per pengguna
  Google — untuk boot tool beberapa kali sehari per device tidak masalah.

## Struktur data

Tersimpan satu blok JSON di **Script Properties** (`rejoin_db`):

```json
{
  "keys":  { "KODE123": { "maxDevices": 3, "note": "", "created": "...", "revoked": false } },
  "binds": { "deviceIdHex": "KODE123" }
}
```