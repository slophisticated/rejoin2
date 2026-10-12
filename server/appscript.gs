// =============================================================
// Rejoin License Server — Google Apps Script Web App
// -------------------------------------------------------------
// Skala prive (<50 user), gratis, tanpa install CLI.
//
// DEPLOY:
//   1) Buka https://script.google.com  -> New project
//   2) Tempel seluruh isi file ini
//   3) Extensions > App Script property  -> Set HMAC_SECRET:
//        Property:  HMAC_SECRET   -> isi string rahasia panjang acak
//   4) Deploy > New deployment > Type: Web app
//        Execute as: Me
//        Who has access: Anyone
//   5) Salin URL .../exec  -> isi ke config  license.serverUrl
//      (URL dipakai CLIENT via POST JSON; redirect otomatis ditangani -L)
//
// ADMIN (jalankan langsung dari EDITOR sebagai fungsi):
//   createKey("KODE123", 3, "note")   -> buat kode key, max 3 device
//   listKeys()                        -> daftar semua key + device terikat
//   revokeDevice("deviceIdHex")       -> cabut satu device (harus re-register)
//   revokeKey("KODE123")              -> cabut SEMUA device key tsb (lebih ampuh)
//   wipeAll()                         -> reset total (hati-hati)
// =============================================================

var DB_PROP = 'rejoin_db';

function adminSecret_() {
  return PropertiesService.getScriptProperties().getProperty('HMAC_SECRET') || '';
}

function hmacHex_(payload) {
  var sig = Utilities.computeHmacSha256Signature(payload, adminSecret_());
  var hex = '';
  for (var i = 0; i < sig.length; i++) {
    var b = sig[i];
    if (b < 0) b += 256;
    hex += ('0' + b.toString(16)).slice(-2);
  }
  return hex;
}

function loadDb_() {
  var raw = PropertiesService.getScriptProperties().getProperty(DB_PROP);
  try {
    var db = JSON.parse(raw || '{}');
  } catch (e) { db = {}; }
  if (!db.keys) db.keys = {};
  if (!db.binds) db.binds = {};
  return db;
}

function saveDb_(db) {
  PropertiesService.getScriptProperties().setProperty(DB_PROP, JSON.stringify(db));
}

function withLock_(fn) {
  var lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    var db = loadDb_();
    var out = fn(db);
    saveDb_(db);
    return out;
  } finally {
    lock.releaseLock();
  }
}

function doPost(e) {
  try {
    var body = (e && e.postData && e.postData.contents) || '';
    var req = JSON.parse(body);
    var action = req.action;
    var out;
    if (action === 'register') {
      out = register_(req.key, req.deviceId);
    } else if (action === 'validate') {
      out = validate_(req.deviceId, req.sess);
    } else {
      out = { ok: false, reason: 'unknown_action' };
    }
    return json_({ okCode: 200, body: out });
  } catch (err) {
    return json_({ okCode: 500, body: { ok: false, reason: 'server_error', msg: String(err) } });
  }
}

function doGet() {
  return json_({ okCode: 200, body: { service: 'rejoin-license', ok: true } });
}

function json_(r) {
  return ContentService.createTextOutput(JSON.stringify(r.body))
    .setMimeType(ContentService.MimeType.JSON);
}

// ---------- Core ----------

function register_(key, deviceId) {
  var k = String(key || '').trim();
  if (!k) return { ok: false, reason: 'missing_key' };
  if (!deviceId) return { ok: false, reason: 'missing_device' };

  var res = withLock_(function (db) {
    var meta = db.keys[k];
    if (!meta) return { ok: false, reason: 'key_not_found' };
    if (meta.revoked) return { ok: false, reason: 'key_revoked' };

    // Sudah terdaftar untuk key ini -> return session lama (idempoten)
    if (db.binds[deviceId]) {
      if (db.binds[deviceId] === k) {
        return { ok: true, sess: sessFor_(deviceId), keyFam: k };
      }
      return { ok: false, reason: 'device_bound_other_key' };
    }

    var used = 0;
    for (var d in db.binds) if (db.binds.hasOwnProperty(d) && db.binds[d] === k) used++;
    if (used >= (meta.maxDevices || 1)) return { ok: false, reason: 'slots_full' };

    db.binds[deviceId] = k;
    return { ok: true, sess: sessFor_(deviceId), keyFam: k };
  });
  return res;
}

function validate_(deviceId, sess) {
  var expected = sessFor_(deviceId);
  if (!sess || sess !== expected) return { ok: false, reason: 'bad_session' };

  var db = loadDb_();
  var k = db.binds[deviceId];
  if (!k) return { ok: false, reason: 'not_bound' };
  var meta = db.keys[k];
  if (!meta || meta.revoked) return { ok: false, reason: 'key_revoked' };
  return { ok: true, keyFam: k };
}

function sessFor_(deviceId) {
  return deviceId + '.' + hmacHex_('rejoin::' + deviceId);
}

// ---------- Admin (dijalankan dari editor) ----------

function createKey(keyCode, maxDevices, note) {
  var k = String(keyCode || '').trim();
  if (!k) throw new Error('keyCode wajib diisi');
  var out = withLock_(function (db) {
    if (db.keys[k] && !db.keys[k].revoked) throw new Error('Key sudah ada: ' + k);
    db.keys[k] = {
      maxDevices: (maxDevices && maxDevices > 0) ? maxDevices : 1,
      note: note || '',
      created: new Date().toISOString(),
      revoked: false
    };
    return { ok: true, key: k, info: db.keys[k] };
  });
  Logger.log('createKey -> ' + JSON.stringify(out));
  return out;
}

function revokeKey(keyCode) {
  var out = withLock_(function (db) {
    var k = String(keyCode || '').trim();
    if (!db.keys[k]) throw new Error('Key tidak ada: ' + k);
    db.keys[k].revoked = true;
    return { ok: true, key: k };
  });
  Logger.log('revokeKey -> ' + JSON.stringify(out));
  return out;
}

function revokeDevice(deviceId) {
  var out = withLock_(function (db) {
    var id = String(deviceId || '').trim();
    if (!db.binds[id]) throw new Error('Device tidak terikat: ' + id);
    delete db.binds[id];
    return { ok: true, deviceId: id };
  });
  Logger.log('revokeDevice -> ' + JSON.stringify(out));
  return out;
}

function listKeys() {
  var db = loadDb_();
  var rows = [];
  for (var k in db.keys) {
    if (!db.keys.hasOwnProperty(k)) continue;
    var meta = db.keys[k];
    var devices = [];
    for (var d in db.binds) {
      if (db.binds.hasOwnProperty(d) && db.binds[d] === k) devices.push(d);
    }
    rows.push({
      key: k,
      maxDevices: meta.maxDevices,
      note: meta.note,
      created: meta.created,
      revoked: meta.revoked,
      devices: devices,
      used: devices.length
    });
  }
  rows.sort(function (a, b) { return (b.created || '').localeCompare(a.created || ''); });
  Logger.log('listKeys -> ' + JSON.stringify({ count: rows.length }));
  return rows;
}

function wipeAll() {
  PropertiesService.getScriptProperties().deleteProperty(DB_PROP);
  Logger.log('wipeAll: DB direset (semua key & binding dihapus).');
  return { ok: true };
}