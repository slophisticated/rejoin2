import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readEnv, accountOf } from '../src/env.js';
import { createApi } from '../src/http.js';
import { Store, keyOf } from '../src/store.js';
import { Handler } from '../src/commands/handler.js';
import { Replies } from '../src/replies.js';
import { ack, guild, interaction, png, snapshot } from '../test-support/fixtures.js';

const me = '11111111111111111';
const friend = '22222222222222222';
const mySecret = 'm'.repeat(40);
const friendSecret = 'f'.repeat(40);
const base = { DISCORD_TOKEN: 'test-token-only', APP_ID: '34567890123456789', GUILD_ID: guild };

test('OWNERS gives each owner their own secret/account; legacy pair still works next to it', () => {
  const config = readEnv({ ...base, OWNERS: `${me}:${mySecret}, ${friend}:${friendSecret}` });
  assert.equal(config.accounts.get(me), accountOf(mySecret));
  assert.equal(config.accounts.get(friend), accountOf(friendSecret));
  assert.notEqual(config.accounts.get(me), config.accounts.get(friend));
  assert.equal(config.secrets.length, 2); assert.equal(config.owners.size, 2);
  const shared = readEnv({ ...base, OWNERS: `${me}:${mySecret},${friend}:${mySecret}` });
  assert.equal(shared.accounts.get(me), shared.accounts.get(friend)); assert.equal(shared.secrets.length, 1);
  const mixed = readEnv({ ...base, OWNERS: `${friend}:${friendSecret}`, OWNER_IDS: me, DEVICE_SECRET: mySecret });
  assert.equal(mixed.accounts.get(me), ''); assert.equal(mixed.secrets.length, 2);
  for (const OWNERS of [`${me}:short`, `x:${mySecret}`, `${me}`, `${me}:${mySecret},${me}:${friendSecret}`]) {
    assert.throws(() => readEnv({ ...base, OWNERS }));
  }
  assert.throws(() => readEnv(base), /OWNER_IDS/);
});

function twoOwners() {
  let time = 1_000_000;
  const now = () => time;
  const store = new Store({ now });
  const accounts = new Map([[me, accountOf(mySecret)], [friend, accountOf(friendSecret)]]);
  const replies = new Replies({ store, now });
  const handler = new Handler({ store, replies, now, accounts, guildId: guild });
  return { store, replies, handler, accounts, now, advance: ms => { time += ms; } };
}

test('same device name under two owners stays separate over HTTP, ACK and upload', async t => {
  const h = twoOwners();
  const server = createApi({ store: h.store, now: h.now, secrets: [
    { account: accountOf(mySecret), secret: mySecret }, { account: accountOf(friendSecret), secret: friendSecret }] });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); h.replies.close(); }));
  const url = `http://127.0.0.1:${server.address().port}`;
  const send = (secret, path, value, type = 'application/json') => fetch(url + path, { method: 'POST',
    headers: { authorization: `Bearer ${secret}`, 'content-type': type }, body: Buffer.isBuffer(value) ? value : JSON.stringify(value) });

  assert.equal((await send(mySecret, '/api/sync', snapshot('RF-01'))).status, 200);
  assert.equal((await send(friendSecret, '/api/sync', snapshot('RF-01'))).status, 200);
  assert.equal(h.store.devices.size, 2);
  const mine = keyOf(accountOf(mySecret), 'RF-01');
  const theirs = keyOf(accountOf(friendSecret), 'RF-01');
  const shot = h.store.enqueue(mine, 'screenshot');
  h.advance(4000);
  // The friend's device never receives my command, and cannot ACK or upload for it.
  assert.deepEqual((await (await send(friendSecret, '/api/sync', snapshot('RF-01'))).json()).commands, []);
  assert.equal((await (await send(mySecret, '/api/sync', snapshot('RF-01'))).json()).commands[0].id, shot.id);
  assert.equal((await send(friendSecret, `/api/upload/${shot.id}`, png, 'image/png')).status, 404);
  await send(friendSecret, '/api/ack', ack(shot, { device: 'RF-01', data: { uploaded: true } }));
  assert.equal(h.store.commands.get(shot.id).state, 'sent');
  assert.equal((await send(mySecret, `/api/upload/${shot.id}`, png, 'image/png')).status, 200);
  await send(mySecret, '/api/ack', ack(shot, { device: 'RF-01', data: { uploaded: true } }));
  assert.equal(h.store.commands.has(shot.id), false);
  assert.ok(h.store.devices.has(theirs));
});

test('each owner only sees and controls their own devices', async () => {
  const h = twoOwners();
  h.store.sync(snapshot('RF-01'), h.accounts.get(me));
  h.store.sync(snapshot('RF-02'), h.accounts.get(me));
  h.store.sync(snapshot('TW-01'), h.accounts.get(friend));
  const as = (user, path, values, extra = {}) => interaction(path, values, { user: { id: user }, ...extra });

  const list = as(friend, 'devices', {}); await h.handler.handle(list);
  const shown = JSON.stringify(list.edits);
  assert.match(shown, /TW-01/); assert.doesNotMatch(shown, /RF-0/);

  const auto = as(friend, 'restart', { clones: 'all' }, { isAutocomplete: () => true, options: {
    ...interaction('restart').options, getFocused: () => ({ name: 'device', value: '' }) } });
  await h.handler.handle(auto);
  assert.deepEqual(auto.responses[0].map(c => c.value), ['TW-01']);

  // Only one device in the friend's account: it is picked without the device option.
  await h.handler.handle(as(friend, 'restart', { clones: 'all' }));
  // Naming my device from the friend's account does not reach it.
  const blocked = as(friend, 'restart', { clones: 'all', device: 'RF-01' }); await h.handler.handle(blocked);
  assert.match(blocked.edits.at(-1).content, /tidak ditemukan/);
  await h.handler.handle(as(me, 'game', { device: 'all', preset: 'B' }));
  const targets = [...h.store.commands.values()].map(c => `${c.account === h.accounts.get(me) ? 'me' : 'friend'}:${c.name}`).sort();
  assert.deepEqual(targets, ['friend:TW-01', 'me:RF-01', 'me:RF-02']);
  h.replies.close();
});

test('rename only clashes inside the same account; persistence keeps accounts', async t => {
  const dataDir = await mkdtemp(join(tmpdir(), 'rejoin-bot-acc-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  let time = 1_000_000;
  const store = new Store({ now: () => time, dataDir });
  const a = accountOf(mySecret), b = accountOf(friendSecret);
  store.sync(snapshot('RF-01'), a); store.sync(snapshot('TW-01'), b);
  const rename = store.enqueue(keyOf(a, 'RF-01'), 'device_rename', { name: 'TW-01' });
  time += 4000; store.sync(snapshot('RF-01'), a);
  store.ack(ack(rename, { device: 'RF-01' }), a);
  assert.ok(store.devices.has(keyOf(a, 'TW-01')) && store.devices.has(keyOf(b, 'TW-01')));
  store.sync(snapshot('RF-09'), a);
  assert.throws(() => store.enqueue(keyOf(a, 'RF-09'), 'device_rename', { name: 'TW-01' }), /sudah dipakai/);
  const pending = store.enqueue(keyOf(b, 'TW-01'), 'status');
  await store.close();
  const restored = new Store({ now: () => time, dataDir }); await restored.load();
  assert.equal(restored.view(a).devices.has('TW-01'), true);
  assert.equal(restored.view(b).devices.size, 1);
  assert.equal(restored.commands.get(pending.id).account, b);
  // A version-1 state file (single secret) loads into the legacy account.
  await writeFile(join(dataDir, 'state.json'), JSON.stringify({ version: 1,
    devices: [{ name: 'OLD', snapshot: snapshot('OLD'), lastSeen: time }], commands: [] }));
  const legacy = new Store({ now: () => time, dataDir }); await legacy.load();
  assert.equal(legacy.view('').devices.has('OLD'), true);
  assert.equal(JSON.parse(await readFile(join(dataDir, 'state.json'), 'utf8')).version, 1);
});

test('device remove: offline only, own account only, confirmed, pending commands settled', async () => {
  const h = twoOwners();
  h.store.sync(snapshot('OLD-01'), h.accounts.get(me));
  h.store.sync(snapshot('TW-01'), h.accounts.get(friend));
  const as = (user, path, values, extra = {}) => interaction(path, values, { user: { id: user }, ...extra });
  const mine = keyOf(h.accounts.get(me), 'OLD-01');

  // Online: refused before any confirmation.
  const online = as(me, 'device remove', { device: 'OLD-01' }); await h.handler.handle(online);
  assert.match(online.edits.at(-1).content, /masih online/);
  assert.equal(h.handler.sessions.size, 0);

  h.advance(100_000);
  const pending = h.store.enqueue(mine, 'status');
  const results = []; h.store.on('result', (c, r) => results.push([c.id, r.ok]));
  // Another owner cannot even see it.
  const other = as(friend, 'device remove', { device: 'OLD-01' }); await h.handler.handle(other);
  assert.match(other.edits.at(-1).content, /tidak ditemukan/);

  await h.handler.handle(as(me, 'device remove', { device: 'OLD-01' }));
  assert.ok(h.store.devices.has(mine), 'removed before confirmation');
  const id = [...h.handler.sessions.keys()][0];
  const confirm = as(me, '', {}, { isButton: () => true, customId: `confirm:${id}` });
  await h.handler.handle(confirm);
  assert.equal(h.store.devices.has(mine), false);
  assert.ok(h.store.devices.has(keyOf(h.accounts.get(friend), 'TW-01')));
  assert.deepEqual(results, [[pending.id, false]]);
  assert.equal(h.store.commands.size, 0);
  assert.match(confirm.edits.at(-1).content, /dihapus/);
  // A device that syncs again simply comes back.
  h.store.sync(snapshot('OLD-01'), h.accounts.get(me));
  assert.ok(h.store.devices.has(mine));
  h.replies.close();
});
