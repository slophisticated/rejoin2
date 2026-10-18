import { createServer } from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';

export const JSON_LIMIT = 512 * 1024;
export const PNG_LIMIT = 8 * 1024 * 1024;
const PNG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const fail = (code, message) => Object.assign(new Error(message), { code });
const digest = s => createHash('sha256').update(s).digest();

export function validateSnapshot(b) {
  if (!object(b) || b.protocol !== 1 || typeof b.device !== 'string' || !b.device.trim() || b.device.length > 200
    || typeof b.version !== 'string' || !Number.isFinite(b.time) || !object(b.presets)
    || !Array.isArray(b.instances) || !Array.isArray(b.settings)) throw fail(400, 'invalid_snapshot');
  if (!b.instances.every(i => object(i) && (typeof i.id === 'number' || typeof i.id === 'string')
    && typeof i.name === 'string' && typeof i.package === 'string' && typeof i.status === 'string')) throw fail(400, 'invalid_instances');
  if (!b.settings.every(s => object(s) && typeof s.key === 'string' && ['int', 'bool', 'string'].includes(s.type))) throw fail(400, 'invalid_settings');
  if (b.deviceId != null && (typeof b.deviceId !== 'string' || !/^[0-9a-f]{16,64}$/i.test(b.deviceId))) throw fail(400, 'invalid_device_id');
  for (const key of ['scripts', 'autoexecute']) {
    if (b[key] != null && (!Array.isArray(b[key]) || !b[key].every(s => object(s) && typeof s.name === 'string'))) throw fail(400, 'invalid_scripts');
  }
  return { ...b, scripts: b.scripts || [], autoexecute: b.autoexecute || [], defaultPreset: b.defaultPreset || '' };
}

async function body(req, limit) {
  const length = req.headers['content-length'];
  if (length && Number(length) > limit) { req.resume(); throw fail(413, 'payload_too_large'); }
  let size = 0;
  const chunks = [];
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > limit) {
      // Drain remaining input without buffering it; keep the connection usable for the error response.
      req.resume();
      throw fail(413, 'payload_too_large');
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function createApi({ store, secret, secrets = [{ account: '', secret }], now = Date.now, render = false, log = () => {} }) {
  const expected = secrets.map(s => ({ account: s.account, digest: digest(s.secret) }));
  // Compare against every secret (no early exit) so timing does not reveal which one matched.
  const accountFor = token => {
    const d = digest(token);
    let found = null;
    for (const e of expected) if (timingSafeEqual(d, e.digest) && found === null) found = e.account;
    return found;
  };
  const failedAuth = new Map();
  const server = createServer(async (req, res) => {
    const reply = (status, value) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify(value));
      if (status >= 400) log(`http ${status}`);
    };
    try {
      const path = new URL(req.url, 'http://localhost').pathname;
      if (path === '/health' && req.method === 'GET') return reply(200, { ok: true, devices: store.devices.size });
      const upload = /^\/api\/upload\/(c_[A-Za-z0-9_-]+)$/.exec(path);
      if (!['/api/sync', '/api/ack'].includes(path) && !upload) { req.resume(); return reply(404, { error: 'not_found' }); }
      const header = req.headers.authorization || '';
      const bearer = /^Bearer (.+)$/.exec(header);
      const account = bearer ? accountFor(bearer[1]) : null;
      if (account === null) {
        const ip = render ? String(req.headers['x-forwarded-for'] || req.socket.remoteAddress).split(',').at(-1).trim() : req.socket.remoteAddress;
        const time = now();
        for (const [key, bucket] of failedAuth) if (time - bucket.start >= 60_000) failedAuth.delete(key);
        const bucket = failedAuth.get(ip) || { start: time, count: 0 };
        bucket.count++;
        failedAuth.set(ip, bucket);
        req.resume();
        return reply(bucket.count > 60 ? 429 : 401, { error: bucket.count > 60 ? 'rate_limited' : 'unauthorized' });
      }
      if (req.method !== 'POST') { req.resume(); return reply(405, { error: 'method_not_allowed' }); }
      const media = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
      if (media !== (upload ? 'image/png' : 'application/json')) { req.resume(); return reply(415, { error: 'unsupported_media_type' }); }
      if (upload) {
        if (!store.canUpload(upload[1], account)) { req.resume(); return reply(404, { error: 'not_found' }); }
        const buffer = await body(req, PNG_LIMIT);
        if (!buffer.subarray(0, 8).equals(PNG)) return reply(400, { error: 'invalid_png' });
        if (!store.upload(upload[1], buffer, account)) return reply(404, { error: 'not_found' });
        return reply(200, { ok: true });
      }
      const raw = await body(req, JSON_LIMIT);
      let b;
      try { b = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw)); }
      catch { throw fail(400, 'invalid_json'); }
      if (path === '/api/sync') {
        const commands = store.sync(validateSnapshot(b), account);
        if (commands === null) return reply(429, { error: 'rate_limited' });
        log(`sync ${JSON.stringify(b.device)} commands=${commands.length} 200`);
        return reply(200, { commands });
      }
      if (!object(b) || b.protocol !== 1 || typeof b.device !== 'string' || typeof b.id !== 'string'
        || typeof b.ok !== 'boolean' || typeof b.message !== 'string') throw fail(400, 'invalid_ack');
      if (b.ok && b.data && store.commands.get(b.id)?.type === 'status') validateSnapshot(b.data);
      store.ack(b, account);
      return reply(200, { ok: true });
    } catch (e) {
      if (!res.headersSent && !res.destroyed) reply(Number.isInteger(e.code) ? e.code : 500, { error: Number.isInteger(e.code) ? e.message : 'internal_error' });
    }
  });
  server.requestTimeout = 75_000;
  server.headersTimeout = 15_000;
  return server;
}
