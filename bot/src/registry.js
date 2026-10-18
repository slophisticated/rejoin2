import { createHash } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

// HWIDs registered with /hwid redeem: hash(HWID) -> owner Discord ID. A device then syncs
// with just its HWID (header X-Rejoin-Hwid), no key on the device. The list survives
// redeploys in DATA_DIR/hwid.json (Railway volume) and/or as one message per HWID in a
// private Discord channel (HWID_CHANNEL_ID). Only hashes are stored, never the HWID.
export const HWID_PATTERN = /^[0-9a-f]{16,64}$/i;
const LINE = /^rejoin-hwid v1 ([0-9a-f]{64}) (\d{17,20})$/;
const hash = hwid => createHash('sha256').update(`rejoin-hwid|${hwid.toLowerCase()}`).digest('hex');

export class HwidRegistry {
  constructor({ channelId = null, dataDir = null, log = () => {} } = {}) {
    this.channelId = channelId;
    this.dataDir = dataDir;
    this.writeChain = Promise.resolve();
    this.log = log;
    this.byHash = new Map(); // hash -> { owner, messageId }
    this.channel = null;
  }

  get persistent() { return Boolean(this.channel || this.dataDir); }

  async loadFile() {
    if (!this.dataDir) return;
    try {
      const saved = JSON.parse(await readFile(join(this.dataDir, 'hwid.json'), 'utf8'));
      for (const [h, owner] of Object.entries(saved.hwids || {})) {
        if (/^[0-9a-f]{64}$/.test(h) && /^\d{17,20}$/.test(owner) && !this.byHash.has(h)) this.byHash.set(h, { owner, messageId: null });
      }
    } catch (e) { if (e.code !== 'ENOENT') this.log('hwid_file_load_failed'); }
  }

  saveFile() {
    if (!this.dataDir) return Promise.resolve();
    const content = JSON.stringify({ version: 1, hwids: Object.fromEntries([...this.byHash].map(([h, v]) => [h, v.owner])) });
    this.writeChain = this.writeChain.then(async () => {
      await mkdir(this.dataDir, { recursive: true });
      const tmp = join(this.dataDir, 'hwid.json.tmp');
      await writeFile(tmp, content, { mode: 0o600 });
      await rename(tmp, join(this.dataDir, 'hwid.json'));
    }).catch(() => this.log('hwid_file_write_failed'));
    return this.writeChain;
  }

  async load(client) {
    if (!this.channelId) return;
    try {
      const channel = await client.channels.fetch(this.channelId);
      let before;
      for (;;) {
        const batch = await channel.messages.fetch({ limit: 100, before });
        for (const m of batch.values()) {
          const x = m.author?.id === client.user.id ? LINE.exec(m.content) : null;
          // Newest first: the latest registration of a HWID wins.
          if (x && !this.byHash.has(x[1])) this.byHash.set(x[1], { owner: x[2], messageId: m.id });
        }
        if (batch.size < 100) break;
        before = batch.last().id;
      }
      this.channel = channel;
      this.log(`hwid_registry_loaded ${this.byHash.size}`);
    } catch { this.log('hwid_registry_load_failed'); }
  }

  ownerOf(hwid) {
    return typeof hwid === 'string' && HWID_PATTERN.test(hwid) ? this.byHash.get(hash(hwid))?.owner ?? null : null;
  }

  // true = newly registered, false = already registered to this owner.
  async add(hwid, owner) {
    if (!HWID_PATTERN.test(hwid)) throw new Error('HWID tidak valid (hex 16–64 karakter, lihat Menu 9 di Termux).');
    const h = hash(hwid);
    const current = this.byHash.get(h);
    if (current) {
      if (current.owner !== owner) throw new Error('HWID ini sudah didaftarkan orang lain.');
      return false;
    }
    let messageId = null;
    if (this.channel) messageId = (await this.channel.send({ content: `rejoin-hwid v1 ${h} ${owner}`, allowedMentions: { parse: [] } })).id;
    this.byHash.set(h, { owner, messageId });
    await this.saveFile();
    return true;
  }

  async remove(hwid, owner) {
    const h = HWID_PATTERN.test(hwid) ? hash(hwid) : null;
    const current = h && this.byHash.get(h);
    if (!current || current.owner !== owner) throw new Error('HWID itu tidak terdaftar atas nama kamu.');
    if (this.channel && current.messageId) {
      try { await (await this.channel.messages.fetch(current.messageId)).delete(); } catch { this.log('hwid_registry_delete_failed'); }
    }
    this.byHash.delete(h);
    await this.saveFile();
  }
}
