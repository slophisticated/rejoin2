export const SCRIPT_LIMIT = 200 * 1024;
export const present = v => v !== undefined && v !== null;
export const setting = (d, key) => d.snapshot.settings.find(s => s.key === key);
const reject = message => { throw new Error(message); };

export function text(value, label, max, empty = false) {
  if (typeof value !== 'string' || (!empty && !value.trim()) || Buffer.byteLength(value) > max) reject(`${label}: isi teks maksimal ${max} byte.`);
  return value;
}

export function gameLink(link) {
  text(link, 'Link', 300);
  if (/^roblox:\/\//.test(link)) return link;
  // Keep the device's accepted contract; the device remains the final validator.
  if (!/^https:\/\/[A-Za-z0-9.-]*roblox\.com\//.test(link)) reject('Link harus https://…roblox.com/… atau roblox://…');
  return link;
}

export function scriptName(raw, { protectedName = false } = {}) {
  let name = text(raw, 'Nama script', 64).trim();
  if (!/^[A-Za-z0-9_.-]+$/.test(name) || name.startsWith('.')) reject('Nama script hanya huruf/angka/_-. dan tidak diawali titik.');
  if (!/\.(lua|txt)$/.test(name)) name += '.lua';
  if (name.length > 64) reject('Nama script termasuk ekstensi maksimal 64 karakter.');
  if (protectedName && name === 'rejoin_heartbeat.lua') reject('rejoin_heartbeat.lua diatur Rejoin; pakai setting heartbeat.');
  return name;
}

export function scriptContent(content) {
  if (typeof content !== 'string' || !content.trim()) reject('Isi script wajib diisi.');
  if (Buffer.byteLength(content) > SCRIPT_LIMIT) reject('Script terlalu besar (maks 200 KB).');
  if (content.includes('\0')) reject('Script harus file teks, bukan biner.');
  return content;
}

export function loaderUrl(url) {
  text(url, 'URL script', 300);
  if (!/^https:\/\/[A-Za-z0-9.-]+\//.test(url) || /["\\\x00-\x20\x7f]/.test(url)) reject('URL script harus HTTPS yang valid.');
  return url;
}

export function configValue(device, key, raw) {
  const schema = setting(device, key);
  if (!schema || ['remote.url', 'remote.secret'].includes(key)) reject(`Setting ${key} tidak boleh diubah dari bot.`);
  if (schema.type === 'bool') {
    if (typeof raw === 'boolean') return raw;
    const value = String(raw).toLowerCase();
    if (['true', 'on', 'ya', '1', 'nyala'].includes(value)) return true;
    if (['false', 'off', 'tidak', '0', 'mati'].includes(value)) return false;
    reject(`${key}: harus true/false.`);
  }
  if (schema.type === 'int') {
    if (!String(raw).trim() || !Number.isFinite(Number(raw))) reject(`${key}: harus angka.`);
    const value = Math.floor(Number(raw));
    if (present(schema.min) && value < schema.min) reject(`${key}: minimal ${schema.min}.`);
    if (present(schema.max) && value > schema.max) reject(`${key}: maksimal ${schema.max}.`);
    return value;
  }
  const value = String(raw).trim();
  text(value, key, schema.max ?? 300, true);
  if (key === 'webhook.url' && value && !/^https:\/\/[A-Za-z0-9.-]+\/api\/webhooks\//.test(value)) reject('Format URL webhook tidak valid.');
  return value;
}

export function findClone(device, ref) {
  const found = device.snapshot.instances.find(i => String(i.id) === String(ref) || i.name === ref || i.package === ref);
  if (!found) reject(`Clone ${ref} tidak ditemukan di ${device.name}.`);
  return found;
}

export function cloneRefs(device, raw, allowAll = true) {
  if (raw === 'all' && allowAll) return 'all';
  if (typeof raw !== 'string' || !raw.trim()) reject('Pilihan clone wajib diisi.');
  const refs = raw.split(',').map(s => s.trim());
  if (refs.some(s => !s)) reject('Daftar clone tidak boleh punya bagian kosong.');
  return [...new Set(refs.map(ref => findClone(device, ref).id))];
}

export function presetExists(device, key) {
  if (!Object.hasOwn(device.snapshot.presets, key)) reject(`Preset ${key} tidak ada di ${device.name}.`);
  return key;
}

export async function downloadScript(attachment, fetcher = fetch) {
  if (!/\.(lua|txt)$/i.test(attachment.name || '') || attachment.size > SCRIPT_LIMIT) reject('File harus .lua/.txt, maksimal 200 KB.');
  let url;
  try { url = new URL(attachment.url); } catch { reject('URL attachment tidak valid.'); }
  if (url.protocol !== 'https:' || !['cdn.discordapp.com', 'media.discordapp.net'].includes(url.hostname)) reject('Attachment harus berasal dari Discord.');
  const response = await fetcher(url, { signal: AbortSignal.timeout(15_000), redirect: 'error' });
  if (!response.ok || !response.body) reject('Gagal mengunduh attachment.');
  if (Number(response.headers.get('content-length')) > SCRIPT_LIMIT) { await response.body.cancel(); reject('Script terlalu besar (maks 200 KB).'); }
  const reader = response.body.getReader();
  let size = 0;
  const chunks = [];
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > SCRIPT_LIMIT) { await reader.cancel(); reject('Script terlalu besar (maks 200 KB).'); }
      chunks.push(value);
    }
    let content;
    try { content = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)); }
    catch { reject('File harus teks UTF-8 valid.'); }
    if (/[\x01-\x08\x0b\x0c\x0e-\x1f]/.test(content)) reject('File harus teks, bukan biner.');
    return scriptContent(content);
  } finally { reader.releaseLock(); }
}
