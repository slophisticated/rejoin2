const FILE_LIMIT = 200 * 1024;
const ROW_LIMIT = 100;

const headers = {
  device: new Set(['device', 'devicename', 'labeldevice']),
  username: new Set(['usn', 'username', 'user', 'akun', 'robloxusername']),
  date: new Set(['tanggal', 'date']),
  time: new Set(['jam', 'time']),
  daily: new Set(['daily', 'berulang', 'ulangharian']),
  order: new Set(['orderid', 'order']),
  notes: new Set(['notes', 'note', 'catatan', 'keterangan']),
  deleted: new Set(['delete', 'hapus']),
};

const headerKey = value => String(value ?? '').trim().toLowerCase()
  .normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/g, '');

function parseRecords(source, delimiter) {
  const rows = [];
  let row = [], cell = '', quoted = false, afterQuote = false;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (quoted) {
      if (ch === '"' && source[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') { quoted = false; afterQuote = true; }
      else cell += ch;
      continue;
    }
    if (ch === '"') {
      if (cell.trim() || afterQuote) throw new Error('CSV memiliki tanda kutip yang tidak valid.');
      quoted = true;
    } else if (ch === delimiter) {
      row.push(cell.trim()); cell = ''; afterQuote = false;
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && source[i + 1] === '\n') i++;
      row.push(cell.trim());
      if (row.some(value => value !== '')) rows.push(row);
      row = []; cell = ''; afterQuote = false;
    } else {
      if (afterQuote && !/\s/.test(ch)) throw new Error('Ada teks setelah tanda kutip CSV.');
      if (!afterQuote) cell += ch;
    }
  }
  if (quoted) throw new Error('CSV memiliki tanda kutip yang belum ditutup.');
  row.push(cell.trim());
  if (row.some(value => value !== '')) rows.push(row);
  return rows;
}

function headerMap(row) {
  const result = {};
  for (const [name, aliases] of Object.entries(headers)) {
    const index = row.findIndex(value => aliases.has(headerKey(value)));
    if (index >= 0) result[name] = index;
  }
  return result;
}

function parseDate(value) {
  const raw = String(value ?? '').trim();
  let m = raw.match(/^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{4}))?$/);
  if (m) {
    const day = Number(m[1]), month = Number(m[2]), year = m[3] ? Number(m[3]) : null;
    if (!validCalendar(day, month, year ?? 2024)) return null;
    return `${String(day).padStart(2, '0')}/${String(month).padStart(2, '0')}${year ? `/${year}` : ''}`;
  }

  const months = { jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3, apr: 4, april: 4,
    may: 5, mei: 5, jun: 6, june: 6, jul: 7, july: 7, aug: 8, agu: 8, august: 8,
    sep: 9, sept: 9, september: 9, oct: 10, okt: 10, october: 10, oktober: 10,
    nov: 11, november: 11, dec: 12, des: 12, december: 12, desember: 12 };
  const monthPattern = '([A-Za-z]+)';
  m = raw.match(new RegExp(`^(\\d{1,2})[- ]${monthPattern}(?:[- ,](\\d{4}))?$`, 'i'))
    || raw.match(new RegExp(`^${monthPattern}[- ](\\d{1,2})(?:,?[- ](\\d{4}))?$`, 'i'));
  if (!m) return null;
  let day, monthName, year;
  if (/^\d/.test(m[1])) { day = Number(m[1]); monthName = m[2]; year = m[3] ? Number(m[3]) : null; }
  else { monthName = m[1]; day = Number(m[2]); year = m[3] ? Number(m[3]) : null; }
  const month = months[monthName.toLowerCase()];
  if (!month || !validCalendar(day, month, year ?? 2024)) return null;
  return `${String(day).padStart(2, '0')}/${String(month).padStart(2, '0')}${year ? `/${year}` : ''}`;
}

function validCalendar(day, month, year) {
  if (!Number.isInteger(day) || !Number.isInteger(month) || month < 1 || month > 12) return false;
  const max = [31, year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28,
    31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  return day >= 1 && day <= max;
}

function isFutureAlarm(date, time, now) {
  const [day, month, yearValue] = date.split('/').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  const local = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta', year: 'numeric', month: '2-digit', day: '2-digit' })
    .formatToParts(new Date(now)).map(part => [part.type, part.value]));
  const currentYear = Number(local.year);
  const firstYear = yearValue || currentYear;
  const lastYear = yearValue || currentYear + 8;
  for (let year = firstYear; year <= lastYear; year++) {
    if (!validCalendar(day, month, year)) continue;
    const due = Date.UTC(year, month - 1, day, hour, minute) / 1000 - 7 * 60 * 60;
    if (due > now / 1000) return true;
  }
  return false;
}

function parseTime(value) {
  const m = String(value ?? '').trim().match(/^(\d{1,2}):([0-5]\d)$/);
  if (!m || Number(m[1]) > 23) return null;
  return `${String(Number(m[1])).padStart(2, '0')}:${m[2]}`;
}

function truthy(value) {
  return ['1', 'true', 'yes', 'y', 'ya', 'iya', 'x', '✓', '✔', '☑', 'checked'].includes(String(value ?? '').trim().toLowerCase());
}

export async function downloadAlarmCsv(attachment, fetcher = fetch) {
  if (!/\.csv$/i.test(attachment?.name || '') || !Number.isFinite(attachment?.size) || attachment.size > FILE_LIMIT) {
    throw new Error('Upload file .csv maksimal 200 KB. Ekspor spreadsheet sebagai CSV dulu.');
  }
  let url;
  try { url = new URL(attachment.url); } catch { throw new Error('URL attachment CSV tidak valid.'); }
  if (url.protocol !== 'https:' || !['cdn.discordapp.com', 'media.discordapp.net'].includes(url.hostname)) {
    throw new Error('File harus diunggah langsung ke Discord.');
  }
  const response = await fetcher(url, { signal: AbortSignal.timeout(15_000), redirect: 'error' });
  if (!response.ok || !response.body) throw new Error('Gagal mengunduh CSV dari Discord.');
  if (Number(response.headers.get('content-length')) > FILE_LIMIT) {
    await response.body.cancel();
    throw new Error('CSV terlalu besar (maksimal 200 KB).');
  }
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > FILE_LIMIT) { await reader.cancel(); throw new Error('CSV terlalu besar (maksimal 200 KB).'); }
      chunks.push(value);
    }
    let text;
    try { text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)); }
    catch { throw new Error('CSV harus menggunakan UTF-8.'); }
    if (/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(text)) throw new Error('CSV berisi karakter kontrol yang tidak didukung.');
    return text.replace(/^\uFEFF/, '');
  } finally { reader.releaseLock(); }
}

export function parseAlarmCsv(text) {
  const candidates = [',', ';', '\t'].map(delimiter => {
    try { const rows = parseRecords(text, delimiter); return { rows, map: headerMap(rows[0] || []) }; }
    catch { return null; }
  }).filter(Boolean);
  const parsed = candidates.find(candidate => ['device', 'username', 'date', 'time'].every(key => candidate.map[key] !== undefined));
  if (!parsed) throw new Error('Header wajib: DEVICE, USN, TANGGAL, JAM. Kolom NOTES, ORDER ID, dan Delete opsional.');
  const { rows, map } = parsed;
  const dataRows = rows.slice(1);
  if (!dataRows.length) throw new Error('CSV belum berisi baris alarm.');
  if (dataRows.length > ROW_LIMIT) throw new Error(`Maksimal ${ROW_LIMIT} baris per import.`);
  return dataRows.map((cells, index) => {
    const get = key => map[key] === undefined ? '' : String(cells[map[key]] ?? '').trim();
    const row = { rowNumber: index + 2, orderId: get('order'), deviceRef: get('device'), username: get('username'),
      dateRaw: get('date'), timeRaw: get('time'), daily: truthy(get('daily')), notes: get('notes'),
      deleted: truthy(get('deleted')), status: 'invalid', error: '' };
    if (row.deleted) { row.status = 'skipped'; row.error = 'Delete dicentang; baris dilewati.'; return row; }
    if (!row.deviceRef || !row.username || !row.dateRaw || !row.timeRaw) { row.error = 'DEVICE, USN, TANGGAL, dan JAM wajib diisi.'; return row; }
    row.date = parseDate(row.dateRaw);
    if (!row.date) { row.error = 'Tanggal tidak valid; gunakan DD/MM/YYYY atau 20-Oct.'; return row; }
    row.time = parseTime(row.timeRaw);
    if (!row.time) { row.error = 'Jam tidak valid; gunakan format 24 jam seperti 18:40.'; return row; }
    row.status = 'parsed';
    return row;
  });
}

export function resolveAlarmRows(rows, devices, now = Date.now()) {
  const deviceList = [...devices.values()];
  const resolved = rows.map(row => {
    if (row.status !== 'parsed') return row;
    const ref = row.deviceRef.trim().toLocaleLowerCase();
    const matches = deviceList.filter(device => {
      const label = device.snapshot.settings.find(setting => setting.key === 'webhook.deviceName')?.value;
      return [device.name, label].some(value => typeof value === 'string' && value.trim().toLocaleLowerCase() === ref);
    });
    if (matches.length !== 1) {
      row.status = 'invalid';
      row.error = matches.length ? 'DEVICE cocok ke lebih dari satu device; ubah label agar unik.' : `DEVICE “${row.deviceRef}” tidak cocok dengan nama/label di /devices.`;
      return row;
    }
    const device = matches[0];
    const users = device.snapshot.instances.filter(instance => String(instance.username || '').trim().toLocaleLowerCase() === row.username.toLocaleLowerCase());
    if (users.length !== 1) {
      row.status = 'invalid';
      row.error = users.length ? `USN “${row.username}” cocok ke beberapa clone di ${device.name}.` : `USN “${row.username}” tidak ditemukan di snapshot ${device.name}.`;
      return row;
    }
    if (!isFutureAlarm(row.date, row.time, now)) {
      row.status = 'invalid';
      row.error = 'Tanggal dan jam harus masih di masa depan menurut WIB.';
      return row;
    }
    row.deviceKey = device.key;
    row.deviceName = device.name;
    row.cloneId = users[0].id;
    row.cloneName = users[0].name;
    row.previousAlarm = users[0].logoutAlarm ? structuredClone(users[0].logoutAlarm) : null;
    row.status = 'ready';
    return row;
  });

  const grouped = new Map();
  for (const row of resolved) if (row.status === 'ready') {
    const key = `${row.deviceKey}\u0000${row.cloneId}`;
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(row);
  }
  for (const duplicates of grouped.values()) if (duplicates.length > 1) {
    for (const row of duplicates) { row.status = 'invalid'; row.error = 'Ada beberapa baris untuk clone yang sama; sisakan satu jadwal.'; }
  }
  return resolved;
}

export function alarmImportReport(rows) {
  const quote = value => `"${String(value ?? '').replaceAll('"', '""').replace(/[\r\n]+/g, ' ')}"`;
  const lines = [['baris', 'status', 'device', 'clone', 'usn', 'tanggal', 'jam', 'ulangan', 'order_id', 'notes', 'hasil']
    .map(quote).join(',')];
  for (const row of rows) {
    const result = row.status === 'ready'
      ? row.previousAlarm ? 'siap; jadwal lama akan diganti setelah konfirmasi' : 'siap'
      : row.error;
    lines.push([row.rowNumber, row.status, row.deviceName || row.deviceRef, row.cloneName || '', row.username,
      row.date || row.dateRaw, row.time || row.timeRaw, row.daily ? 'harian' : 'sekali', row.orderId, row.notes, result].map(quote).join(','));
  }
  return Buffer.from(lines.join('\r\n'), 'utf8');
}
