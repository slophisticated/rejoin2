import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readEnv } from '../src/env.js';
import { createApi } from '../src/http.js';
import { HwidRegistry } from '../src/registry.js';
import { Store } from '../src/store.js';
import { Replies } from '../src/replies.js';
import { Handler } from '../src/commands/handler.js';
import { guild, interaction, snapshot } from '../test-support/fixtures.js';

const me = '11111111111111111';
const apeng = '22222222222222222';
const hwidA = 'de66d5e6b3038d94';
const hwidB = '0123456789abcdef0123456789abcdef';
const base = { DISCORD_TOKEN: 'test-token-only', APP_ID: '34567890123456789', GUILD_ID: guild };

// Minimal Discord channel: keeps the messages the bot writes.
function fakeChannel() {
  const msgs = new Map(); let n = 0;
  const wrap = m => ({ ...m, delete: async () => { msgs.delete(m.id); } });
  return {
    msgs,
    send: async ({ content }) => { const m = { id: String(++n), content, author: { id: 'bot' } }; msgs.set(m.id, m); return m; },
    messages: {
      fetch: async arg => {
        if (typeof arg === 'string') return wrap(msgs.get(arg));
        const list = [...msgs.values()].reverse();
        const coll = new Map(list.map(m => [m.id, m]));
        coll.last = () => list.at(-1);
        return coll;
      },
    },
  };
}
const fakeClient = channel => ({ user: { id: 'bot' }, channels: { fetch: async () => channel } });

test('env: HWID-only setup needs no DEVICE_SECRET; HWID_USERS get their own account', () => {
  const c = readEnv({ ...base, OWNER_IDS: me, HWID_USERS: apeng, HWID_CHANNEL_ID: '33333333333333333' });
  assert.equal(c.secrets.length, 0);
  assert.equal(c.accounts.get(me), ''); assert.equal(c.accounts.get(apeng), `u${apeng}`);
  assert.equal(c.hwidChannelId, '33333333333333333');
  assert.throws(() => readEnv({ ...base, OWNER_IDS: me, HWID_CHANNEL_ID: 'x' }), /HWID_CHANNEL_ID/);
});

test('registry: register once, survives a restart through the channel, only hashes stored', async () => {
  const channel = fakeChannel();
  const reg = new HwidRegistry({ channelId: '1' }); await reg.load(fakeClient(channel));
  assert.equal(reg.persistent, true);
  assert.equal(await reg.add(hwidA, apeng), true);
  assert.equal(await reg.add(hwidA.toUpperCase(), apeng), false);
  await assert.rejects(reg.add(hwidA, me), /orang lain/);
  await assert.rejects(reg.add('zz', me), /HWID tidak valid/);
  assert.ok(![...channel.msgs.values()].some(m => m.content.includes(hwidA)));
  const again = new HwidRegistry({ channelId: '1' }); await again.load(fakeClient(channel));
  assert.equal(again.ownerOf(hwidA), apeng); assert.equal(again.ownerOf(hwidB), null);
  await assert.rejects(again.remove(hwidA, me), /tidak terdaftar/);
  await again.remove(hwidA, apeng);
  assert.equal(again.ownerOf(hwidA), null); assert.equal(channel.msgs.size, 0);
});

test('HTTP: a registered HWID syncs with no secret into its owner account', async t => {
  const store = new Store();
  const reg = new HwidRegistry(); await reg.add(hwidA, apeng); await reg.add(hwidB, '44444444444444444');
  const server = createApi({ store, secrets: [{ account: '', secret: 's'.repeat(40) }], registry: reg,
    accounts: new Map([[me, ''], [apeng, `u${apeng}`]]) });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => new Promise(r => { server.close(r); server.closeAllConnections(); }));
  const url = `http://127.0.0.1:${server.address().port}/api/sync`;
  const sync = (headers, name) => fetch(url, { method: 'POST', body: JSON.stringify(snapshot(name)),
    headers: { 'content-type': 'application/json', ...headers } });
  assert.equal((await sync({ 'x-rejoin-hwid': hwidA }, 'TW-01')).status, 200);
  assert.ok(store.devices.has(`u${apeng}\u0000TW-01`));
  assert.equal((await sync({ 'x-rejoin-hwid': 'aaaaaaaaaaaaaaaa' }, 'X')).status, 401); // not registered
  assert.equal((await sync({ 'x-rejoin-hwid': hwidB }, 'Y')).status, 401);              // owner not allowed
  assert.equal((await sync({ authorization: `Bearer ${'s'.repeat(40)}` }, 'RF-01')).status, 200); // legacy secret
  assert.ok(store.devices.has('RF-01'));
});

test('/hwid redeem and remove, ephemeral, warn when not persistent', async () => {
  const store = new Store();
  const replies = new Replies({ store });
  const registry = new HwidRegistry();
  const handler = new Handler({ store, replies, registry, accounts: new Map([[apeng, `u${apeng}`]]), guildId: guild });
  const i = interaction('hwid redeem', { hwid: hwidA.toUpperCase() }, { user: { id: apeng } });
  await handler.handle(i);
  assert.ok(i.deferPayload.flags);
  assert.match(i.edits.at(-1).content, /didaftarkan/); assert.match(i.edits.at(-1).content, /redeploy/);
  assert.equal(registry.ownerOf(hwidA), apeng);
  const r = interaction('hwid remove', { hwid: hwidA }, { user: { id: apeng } });
  await handler.handle(r); assert.equal(registry.ownerOf(hwidA), null);
  replies.close();
});

test('registry: volume file (DATA_DIR) keeps registrations across restarts', async t => {
  const dataDir = await mkdtemp(join(tmpdir(), 'rejoin-hwid-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const reg = new HwidRegistry({ dataDir }); await reg.loadFile();
  assert.equal(reg.persistent, true);
  await reg.add(hwidA, apeng); await reg.add(hwidB, me);
  assert.doesNotMatch(await readFile(join(dataDir, 'hwid.json'), 'utf8'), new RegExp(hwidA));
  const again = new HwidRegistry({ dataDir }); await again.loadFile();
  assert.equal(again.ownerOf(hwidA), apeng); assert.equal(again.ownerOf(hwidB), me);
  await again.remove(hwidB, me);
  const third = new HwidRegistry({ dataDir }); await third.loadFile();
  assert.equal(third.ownerOf(hwidB), null); assert.equal(third.ownerOf(hwidA), apeng);
});
