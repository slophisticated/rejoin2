import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

// Devices are scoped per account (one account = one device secret). The legacy single-secret
// setup uses account '' so its keys stay the plain device name.
export const keyOf = (account, name) => account ? `${account}\u0000${name}` : name;

const intervalOf = d => Number(d?.snapshot.settings.find(s => s.key === 'remote.interval')?.value) || 30;

export const renameTarget = (type, args) => type === 'device_rename' ? args.name
  : type === 'config_set' && args.key === 'webhook.deviceName' ? args.value : null;

export class Store extends EventEmitter {
  constructor({ now = Date.now, timeoutMs = 90_000, dataDir = null, log = () => {} } = {}) {
    super();
    this.now = now;
    this.timeoutMs = timeoutMs;
    this.dataDir = dataDir;
    this.log = log;
    this.devices = new Map();
    this.commands = new Map();
    this.uploads = new Map();
    this.persistTimer = null;
    this.writeChain = Promise.resolve();
  }

  async load() {
    if (!this.dataDir) return;
    try {
      const state = JSON.parse(await readFile(join(this.dataDir, 'state.json'), 'utf8'));
      if (![1, 2].includes(state.version) || !Array.isArray(state.devices) || !Array.isArray(state.commands)) throw new Error();
      for (const d of state.devices) {
        if (typeof d.name !== 'string' || !d.snapshot || !Number.isFinite(d.lastSeen)) throw new Error();
        const account = typeof d.account === 'string' ? d.account : '';
        const key = keyOf(account, d.name);
        this.devices.set(key, { ...d, key, account, lastSync: null });
      }
      for (const c of state.commands) {
        if (typeof c.id !== 'string' || !this.devices.has(c.device) || !c.args || !Array.isArray(c.acceptedDevices)) throw new Error();
        const d = this.devices.get(c.device);
        this.commands.set(c.id, { ...c, name: d.name, account: d.account });
      }
    } catch (e) {
      this.devices.clear();
      this.commands.clear();
      if (e.code !== 'ENOENT') this.log('state_load_failed');
    }
  }

  changed() {
    if (!this.dataDir || this.persistTimer) return;
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      void this.persist();
    }, 2000);
    this.persistTimer.unref();
  }

  persist() {
    if (!this.dataDir) return Promise.resolve();
    const content = JSON.stringify({
      version: 2,
      devices: [...this.devices.values()].map(({ account, name, snapshot, lastSeen }) => ({ account, name, snapshot, lastSeen })),
      commands: [...this.commands.values()].filter(c => c.state !== 'awaiting_upload').map(c => ({
        id: c.id, device: c.device, type: c.type, args: c.args, createdAt: c.createdAt,
        state: c.state, sentAt: c.sentAt, resent: c.resent, timedOut: c.timedOut,
        acceptedDevices: c.acceptedDevices,
      })),
    });
    this.writeChain = this.writeChain.then(async () => {
      await mkdir(this.dataDir, { recursive: true });
      const target = join(this.dataDir, 'state.json');
      const tmp = join(this.dataDir, 'state.json.tmp');
      await writeFile(tmp, content, { mode: 0o600 });
      await rename(tmp, target);
    }).catch(() => this.log('state_write_failed'));
    return this.writeChain;
  }

  async close() {
    clearTimeout(this.persistTimer);
    this.persistTimer = null;
    await this.persist();
  }

  online(device) {
    const d = typeof device === 'string' ? this.devices.get(device) : device;
    return Boolean(d && this.now() - d.lastSeen <= intervalOf(d) * 3000);
  }

  // A device renamed on the device itself (Menu 9) syncs under a new name with the same
  // deviceId: fold the old entry into the new one once the old name has gone quiet
  // (2 intervals), so copies of one device that share an id never steal each other.
  absorbRenamed(snapshot, account, key, now) {
    const id = snapshot.deviceId;
    if (typeof id !== 'string' || !id) return;
    for (const d of [...this.devices.values()]) {
      if (d.account !== account || d.key === key || d.snapshot.deviceId !== id) continue;
      if (now - d.lastSeen < intervalOf(d) * 2000) continue;
      this.devices.delete(d.key);
      for (const c of this.commands.values()) {
        if (c.device !== d.key) continue;
        c.device = key;
        c.name = snapshot.device;
        if (!c.acceptedDevices.includes(key)) c.acceptedDevices.push(key);
      }
    }
  }

  // Devices of one account, keyed by their plain name (what commands and autocomplete show).
  view(account = '') {
    const devices = new Map([...this.devices.values()].filter(d => d.account === account).map(d => [d.name, d]));
    return { devices, now: () => this.now(), online: d => this.online(d) };
  }

  assertRename(key, target, exceptId = null) {
    const d = this.devices.get(key);
    const account = d?.account ?? '';
    if (!target || target === (d?.name ?? key)) return;
    if (this.devices.has(keyOf(account, target))) throw new Error('Nama device itu sudah dipakai.');
    for (const c of this.commands.values()) {
      if (c.id !== exceptId && c.account === account && renameTarget(c.type, c.args) === target) throw new Error('Nama device itu sedang dipesan command rename.');
    }
  }

  enqueue(key, type, args = {}) {
    const d = this.devices.get(key);
    if (!d) throw new Error('Device belum dikenal.');
    this.assertRename(key, renameTarget(type, args));
    const device = key;
    const c = {
      id: `c_${randomUUID().replaceAll('-', '')}`, device, name: d.name, account: d.account, type, args: structuredClone(args),
      state: 'queued', createdAt: this.now(), sentAt: null, resent: false,
      timedOut: false, acceptedDevices: [device],
    };
    this.commands.set(c.id, c);
    this.changed();
    return c;
  }

  sync(snapshot, account = '') {
    const now = this.now();
    const key = keyOf(account, snapshot.device);
    const old = this.devices.get(key);
    if (old?.lastSync != null && now - old.lastSync < 4000) return null;
    this.absorbRenamed(snapshot, account, key, now);
    // Two live devices reporting the same name (e.g. both left on the phone model): flag it.
    const clash = old && this.online(old) && old.snapshot.deviceId && snapshot.deviceId && old.snapshot.deviceId !== snapshot.deviceId
      ? now + intervalOf(old) * 3000 : (old?.clashUntil > now ? old.clashUntil : 0);
    this.devices.set(key, { key, account, name: snapshot.device, snapshot: structuredClone(snapshot), lastSeen: now, lastSync: now, clashUntil: clash });
    const commands = [];
    for (const c of this.commands.values()) {
      if (c.device !== key || c.state === 'awaiting_upload') continue;
      if (c.state === 'queued' || (c.state === 'sent' && !c.resent && now - c.sentAt > 60_000
        && !['restart', 'launch_all'].includes(c.type))) {
        if (c.state === 'sent') c.resent = true;
        c.state = 'sent';
        c.sentAt = now;
        if (!c.acceptedDevices.includes(key)) c.acceptedDevices.push(key);
        commands.push({ id: c.id, type: c.type, args: structuredClone(c.args) });
      }
    }
    this.changed();
    return commands;
  }

  moveDevice(c, target) {
    if (!target || target === c.device) return;
    this.assertRename(c.device, target, c.id);
    const oldKey = c.device;
    const device = this.devices.get(oldKey);
    const newKey = keyOf(device.account, target);
    this.devices.delete(oldKey);
    device.key = newKey;
    device.name = target;
    device.snapshot.device = target;
    this.devices.set(newKey, device);
    for (const queued of this.commands.values()) {
      if (queued.device === oldKey) {
        queued.device = newKey;
        queued.name = target;
        if (!queued.acceptedDevices.includes(newKey)) queued.acceptedDevices.push(newKey);
      }
    }
  }

  ack(payload, account = '') {
    const c = this.commands.get(payload.id);
    if (!c || c.state === 'queued' || c.state === 'awaiting_upload' || !c.acceptedDevices.includes(keyOf(account, payload.device))) return;
    let result = { ok: payload.ok, message: payload.message, data: payload.data };
    if (payload.ok) {
      const target = renameTarget(c.type, c.args);
      if (typeof target === 'string' && target) {
        try { this.moveDevice(c, target); }
        catch { result = { ok: false, message: 'Device sudah berubah nama, tapi nama bentrok. Cek /devices setelah sync berikutnya.' }; }
      }
      if (c.type === 'status' && payload.data?.protocol === 1) {
        const d = this.devices.get(c.device);
        d.snapshot = { ...structuredClone(payload.data), device: d.name };
        d.lastSeen = this.now();
      }
    }
    if (c.type === 'screenshot' && result.ok && payload.data?.uploaded === true) {
      c.state = 'awaiting_upload';
      c.ackAt = this.now();
      c.result = { ok: true, message: payload.message };
      if (this.uploads.has(c.id)) this.finish(c, c.result);
      else this.changed();
      return;
    }
    this.finish(c, result);
  }

  canUpload(id, account = '') {
    const c = this.commands.get(id);
    return c?.type === 'screenshot' && (c.account ?? '') === account && ['sent', 'awaiting_upload'].includes(c.state);
  }

  upload(id, buffer, account = '') {
    if (!this.canUpload(id, account)) return false;
    this.uploads.set(id, { buffer, createdAt: this.now() });
    const c = this.commands.get(id);
    if (c.state === 'awaiting_upload') this.finish(c, c.result);
    return true;
  }

  finish(c, result) {
    this.commands.delete(c.id);
    const uploaded = this.uploads.get(c.id);
    this.uploads.delete(c.id);
    this.changed();
    this.emit('result', c, { ...result, buffer: result.ok ? uploaded?.buffer : undefined });
  }

  tick() {
    const now = this.now();
    for (const [id, u] of this.uploads) if (now - u.createdAt >= 300_000) this.uploads.delete(id);
    for (const c of this.commands.values()) {
      if (c.state === 'awaiting_upload' && now - c.ackAt >= 30_000) {
        this.finish(c, { ok: false, message: 'ACK diterima, tapi upload screenshot belum masuk dalam 30 detik.' });
      } else if (!c.timedOut && now - c.createdAt >= this.timeoutMs) {
        c.timedOut = true;
        this.emit('timeout', c);
        this.changed();
      }
    }
  }
}
