import test from 'node:test';
import assert from 'node:assert/strict';
import { makeKey, verifyKey } from '../src/hwid.js';
import { readEnv } from '../src/env.js';
import { createApi } from '../src/http.js';
import { Store } from '../src/store.js';
import { Replies } from '../src/replies.js';
import { Handler } from '../src/commands/handler.js';
import { guild, interaction, snapshot } from '../test-support/fixtures.js';

const master = 'k'.repeat(40);
const me = '11111111111111111';
const apeng = '22222222222222222';
const hwidA = 'de66d5e6b3038d94';
const hwidB = '0123456789abcdef';
const base = { DISCORD_TOKEN: 'test-token-only', APP_ID: '34567890123456789', GUILD_ID: guild };

test('key is bound to its HWID and owner', () => {
  const key = makeKey(master, hwidA, apeng);
  assert.match(key, /^RJ-[0-9a-z]+-[A-Z2-7]{20}$/);
  assert.equal(verifyKey(master, hwidA, key), apeng);
  assert.equal(verifyKey(master, hwidA.toUpperCase(), key), apeng);
  assert.equal(verifyKey(master, hwidB, key), null);
  assert.equal(verifyKey('x'.repeat(40), hwidA, key), null);
  assert.equal(verifyKey(master, hwidA, key.replace(/.$/, c => (c === 'A' ? 'B' : 'A'))), null);
  assert.equal(verifyKey(master, hwidA, key.replace(/^RJ-[0-9a-z]+/, `RJ-${BigInt(me).toString(36)}`)), null);
  assert.throws(() => makeKey(master, 'nothex', apeng), /HWID/);
});

test('env: HWID_USERS get their own account, legacy owners keep theirs', () => {
  const c = readEnv({ ...base, OWNER_IDS: me, DEVICE_SECRET: 's'.repeat(40), HWID_MASTER: master, HWID_USERS: apeng, HWID_REVOKED: hwidB });
  assert.equal(c.accounts.get(me), ''); assert.equal(c.accounts.get(apeng), `u${apeng}`);
  assert.ok(c.hwid.revoked.has(hwidB));
  const only = readEnv({ ...base, OWNER_IDS: me, HWID_MASTER: master });
  assert.equal(only.secrets.length, 0); assert.equal(only.accounts.get(me), '');
  assert.throws(() => readEnv({ ...base, HWID_USERS: apeng }), /HWID_MASTER/);
  assert.throws(() => readEnv({ ...base, OWNER_IDS: me, HWID_MASTER: 'short' }), /HWID_MASTER/);
});

test('HTTP: device key works only with its own HWID header, lands in the owner account', async t => {
  const store = new Store();
  const accounts = new Map([[me, ''], [apeng, `u${apeng}`]]);
  const server = createApi({ store, secrets: [{ account: '', secret: 's'.repeat(40) }], accounts,
    hwid: { master, revoked: new Set([hwidB]) } });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => new Promise(r => { server.close(r); server.closeAllConnections(); }));
  const url = `http://127.0.0.1:${server.address().port}/api/sync`;
  const sync = (key, hwid, name) => fetch(url, { method: 'POST', body: JSON.stringify(snapshot(name)),
    headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json', 'x-rejoin-hwid': hwid } });
  assert.equal((await sync(makeKey(master, hwidA, apeng), hwidA, 'TW-01')).status, 200);
  assert.ok(store.devices.has(`u${apeng}\u0000TW-01`));
  assert.equal((await sync(makeKey(master, hwidA, apeng), 'aaaaaaaaaaaaaaaa', 'X')).status, 401);
  assert.equal((await sync(makeKey(master, hwidB, apeng), hwidB, 'Y')).status, 401); // revoked
  assert.equal((await sync(makeKey(master, hwidA, '33333333333333333'), hwidA, 'Z')).status, 401); // not an owner
  assert.equal((await sync('s'.repeat(40), hwidA, 'RF-01')).status, 200); // legacy secret still works
  assert.ok(store.devices.has('RF-01'));
});

test('/hwid redeem replies with a key for the caller, ephemeral', async () => {
  const store = new Store();
  const replies = new Replies({ store });
  const handler = new Handler({ store, replies, accounts: new Map([[apeng, `u${apeng}`]]), hwid: { master, revoked: new Set() }, guildId: guild });
  const i = interaction('hwid redeem', { hwid: hwidA.toUpperCase() }, { user: { id: apeng } });
  await handler.handle(i);
  assert.ok(i.deferPayload.flags);
  const key = i.edits.at(-1).content.match(/RJ-[0-9a-z]+-[A-Z2-7]{20}/)[0];
  assert.equal(verifyKey(master, hwidA, key), apeng);
  const bad = interaction('hwid redeem', { hwid: 'zz' }, { user: { id: apeng } });
  await handler.handle(bad); assert.match(bad.edits.at(-1).content, /HWID tidak valid/);
  const off = new Handler({ store, replies, accounts: new Map([[apeng, '']]), guildId: guild });
  const j = interaction('hwid redeem', { hwid: hwidA }, { user: { id: apeng } });
  await off.handle(j); assert.match(j.edits.at(-1).content, /HWID\\\\?_MASTER/);
  replies.close();
});
