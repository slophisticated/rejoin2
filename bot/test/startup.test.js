import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Events } from 'discord.js';
import { readEnv } from '../src/env.js';
import { start } from '../src/index.js';
import { guild, owner } from '../test-support/fixtures.js';

const env = { DISCORD_TOKEN: 'test-token-only', APP_ID: '34567890123456789', GUILD_ID: guild, OWNER_IDS: `${owner}, 45678901234567890`, DEVICE_SECRET: 'test-secret-'.repeat(4) };

test('env validates required secrets, IDs, PORT and command timeout without exposing values', () => {
  const config = readEnv(env);
  assert.equal(config.port, 3000); assert.equal(config.timeoutMs, 90_000); assert.equal(config.owners.size, 2);
  for (const key of Object.keys(env)) assert.throws(() => readEnv({ ...env, [key]: '' }), new RegExp(key));
  for (const change of [{ PORT: '-1' }, { PORT: '70000' }, { APP_ID: 'oops' }, { OWNER_IDS: 'x' }, { OWNER_IDS: ',' }, { DEVICE_SECRET: 'short' }, { COMMAND_TIMEOUT_SEC: 'NaN' }]) assert.throws(() => readEnv({ ...env, ...change }));
});

test('startup binds HTTP, registers guild commands automatically, logs readiness, shuts down cleanly', async t => {
  const config = { ...readEnv(env), port: 0 };
  const logs = []; let registrations = 0, login = 0, destroyed = false;
  const client = new EventEmitter();
  client.login = async token => { assert.equal(token, env.DISCORD_TOKEN); login++; client.emit(Events.ClientReady, { user: { tag: 'MockBot#0001' } }); };
  client.destroy = async () => { destroyed = true; };
  const app = await start(config, { log: line => logs.push(line), createClient: () => client, register: async received => { registrations++; assert.equal(received.guildId, guild); } });
  t.after(() => app.close());
  assert.equal(app.server.address().address, '0.0.0.0');
  assert.deepEqual(await (await fetch(`http://127.0.0.1:${app.server.address().port}/health`)).json(), { ok: true, devices: 0 });
  assert.equal(registrations, 1); assert.equal(login, 1);
  assert.ok(logs.includes('listening on :0')); assert.ok(logs.includes('logged in as MockBot#0001'));
  assert.ok(!logs.join('').includes(env.DEVICE_SECRET)); assert.ok(!logs.join('').includes(env.DISCORD_TOKEN));
  await app.close(); assert.equal(destroyed, true);
});

test('registration failure closes HTTP and does not expose underlying token/payload error', async () => {
  const client = new EventEmitter(); let closed = false;
  client.destroy = async () => { closed = true; };
  await assert.rejects(start({ ...readEnv(env), port: 0 }, {
    log: () => {}, createClient: () => client,
    register: async () => { throw new Error(env.DISCORD_TOKEN); },
  }), error => error.message.includes('Startup gagal') && !error.message.includes(env.DISCORD_TOKEN));
  assert.equal(closed, true);
});
