import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { MessageFlags } from 'discord.js';
import { commandDefinitions, routes } from '../src/commands/definitions.js';
import { planDevice, selectDevices } from '../src/commands/planner.js';
import { autocomplete } from '../src/commands/autocomplete.js';
import { configValue, downloadScript, scriptName, SCRIPT_LIMIT } from '../src/commands/validate.js';
import { Handler } from '../src/commands/handler.js';
import { Replies } from '../src/replies.js';
import { chunks, localLines, statusPages } from '../src/format.js';
import { ack, guild, harness, interaction, owner, snapshot } from '../test-support/fixtures.js';

const mappings = [
  ['status', {}, 'status', {}],
  ['game', { preset: 'B' }, 'game', { preset: 'B', rejoin: true }],
  ['game', { preset: 'B', clones: 'Clone1, com.apengjers.v5, 1', rejoin: false }, 'game', { preset: 'B', rejoin: false, clones: [1, 3] }],
  ['default', { preset: 'B' }, 'default_set', { preset: 'B', rejoin: true }],
  ['preset set', { key: 'C', name: 'Garden', link: 'roblox://experiences/3' }, 'preset_set', { key: 'C', name: 'Garden', link: 'roblox://experiences/3', rejoin: false }],
  ['preset remove', { key: 'B' }, 'preset_remove', { key: 'B' }],
  ['clone add', { name: 'Clone4', package: 'com.apengjers.v7' }, 'instance_add', { name: 'Clone4', package: 'com.apengjers.v7' }],
  ['clone edit', { clone: 'Clone1', preset: 'default', link: '-' }, 'instance_edit', { clone: 1, preset: 'default', link: '-' }],
  ['clone remove', { clone: 'com.apengjers.v5' }, 'instance_remove', { clone: 3 }],
  ['clone logout', { clones: 'Clone1, 3' }, 'logout', { clones: [1, 3] }],
  ['restart', { clones: '1,Clone3' }, 'restart', { clones: [1, 3] }],
  ['restart', { clones: 'all' }, 'launch_all', {}],
  ['screenshot', {}, 'screenshot', {}],
  ['config set', { key: 'webhook.interval', value: '600' }, 'config_set', { key: 'webhook.interval', value: 600 }],
  ['webhook set', { url: 'https://discord.com/api/webhooks/1/secret' }, 'config_set', { key: 'webhook.url', value: 'https://discord.com/api/webhooks/1/secret' }],
  ['webhook test', {}, 'webhook_test', {}],
  ['device rename', { name: 'RF-08' }, 'device_rename', { name: 'RF-08' }],
  ['device replace', { message_link: 'https://discord.com/channels/1/2/3' }, 'webhook_use_message', { link: 'https://discord.com/channels/1/2/3' }],
  ['script add', { name: 'farm', code: 'print(1)' }, 'script_add', { name: 'farm.lua', content: 'print(1)' }],
  ['script add', { name: 'hub.txt', file: { name: 'x.txt' }, content: 'print(2)' }, 'script_add', { name: 'hub.txt', content: 'print(2)' }],
  ['script add', { name: 'farm', url: 'https://example.com/farm.lua' }, 'script_add', { name: 'farm.lua', url: 'https://example.com/farm.lua' }],
  ['script view', { name: 'egg' }, 'script_get', { name: 'egg.lua' }],
  ['script remove', { name: 'egg' }, 'script_remove', { name: 'egg.lua' }],
  ['autoexec add', { name: 'hub.txt', rejoin: true }, 'auto_add', { name: 'hub.txt', rejoin: true }],
  ['autoexec remove', { name: 'egg' }, 'auto_remove', { name: 'egg.lua', rejoin: false }],
];

for (const [path, values, type, args] of mappings) {
  test(`mapping ${path}: ${JSON.stringify(values)}`, () => {
    const h = harness();
    assert.deepEqual(planDevice(path, values, h.device()), [{ type, args }]);
  });
}

test('clone logout refuses all and needs confirmation', () => {
  const h = harness();
  assert.throws(() => planDevice('clone logout', { clones: 'all' }, h.device()), /tidak ditemukan/);
  assert.equal(routes['clone logout'].confirm, true);
});

test('all shortcut options map to individual dynamic-schema config_set commands', () => {
  const h = harness();
  const cases = [
    ['webhook options', { interval: 600, screenshot: false, notif_key: true, hide_names: false }, ['webhook.interval', 'webhook.screenshot', 'webhook.events', 'webhook.hideNames']],
    ['window', { enabled: true, columns: 2, gap: 5, overlap: 80 }, ['windowLayout.enabled', 'windowLayout.columns', 'windowLayout.gap', 'windowLayout.overlap']],
    ['saver', { heartbeat: false, enabled: true, fps_cap: 10, disable3d: false }, ['heartbeat.enabled', 'heartbeat.saver.enabled', 'heartbeat.saver.fpsCap', 'heartbeat.saver.disable3d']],
    ['launch', { join_timeout: 100, settle: 10, empty: 3 }, ['launchJoinTimeout', 'launchSettleDelay', 'launchEmptyDelay']],
  ];
  for (const [path, values, keys] of cases) {
    const plans = planDevice(path, values, h.device());
    assert.deepEqual(plans.map(c => c.args.key), keys);
    assert.ok(plans.every(c => c.type === 'config_set'));
    assert.throws(() => planDevice(path, {}, h.device()), /minimal/);
  }
  h.device().snapshot.settings = [];
  assert.throws(() => planDevice('window', { enabled: true }, h.device()), /tidak boleh/);
});

test('registration covers every route, valid Discord option ordering and device contract handler names', async () => {
  const definitions = commandDefinitions();
  assert.equal(definitions.length, 17);
  const seen = [];
  for (const root of definitions) {
    for (const leaf of root.options?.some(o => o.type === 1) ? root.options : [{ ...root, name: null }]) {
      seen.push(root.name + (leaf.name ? ` ${leaf.name}` : ''));
      let optional = false;
      for (const option of leaf.options || []) {
        if (!option.required) optional = true;
        else assert.equal(optional, false, 'required option must precede optional options');
        assert.ok(option.description.length <= 100);
      }
    }
  }
  assert.deepEqual(seen.sort(), Object.keys(routes).sort());
  const lua = await readFile(new URL('../../managers/remote.lua', import.meta.url), 'utf8');
  for (const type of new Set([...mappings.map(m => m[2]), 'config_set'])) assert.match(lua, new RegExp(`function H\\.${type}\\(`));
});

test('schema validation supports device-provided new settings without a hardcoded config list', () => {
  const h = harness();
  h.device().snapshot.settings.push({ key: 'future.setting', type: 'int', min: 2, max: 7, value: 3 });
  assert.equal(configValue(h.device(), 'future.setting', '6.8'), 6);
  for (const value of ['true', 'on', 'ya', '1', 'nyala']) assert.equal(configValue(h.device(), 'heartbeat.enabled', value), true);
  for (const value of ['false', 'off', 'tidak', '0', 'mati']) assert.equal(configValue(h.device(), 'heartbeat.enabled', value), false);
  assert.throws(() => configValue(h.device(), 'future.setting', '1'), /minimal 2/);
  assert.throws(() => configValue(h.device(), 'webhook.interval', 5), /minimal 60/);
  assert.throws(() => configValue(h.device(), 'remote.secret', 'value'), /tidak boleh/);
  assert.throws(() => configValue(h.device(), 'heartbeat.enabled', 'maybe'), /true\/false/);
});

test('device selection requires explicit target when ambiguous; all only where supported', () => {
  const h = harness();
  assert.equal(selectDevices(h.store, 'game')[0].name, 'RF-07');
  h.store.sync(snapshot('RF-08'));
  assert.throws(() => selectDevices(h.store, 'game'), /beberapa/);
  assert.equal(selectDevices(h.store, 'game', 'all').length, 2);
  assert.throws(() => selectDevices(h.store, 'restart', 'all'), /tidak mendukung/);
  assert.throws(() => selectDevices(h.store, 'game', 'missing'), /tidak ditemukan/);
});

test('early validation rejects protected scripts, conflicting sources, bad clones/packages and links', () => {
  const h = harness();
  const invalid = [
    ['script add', { name: 'rejoin_heartbeat', code: 'print(1)' }],
    ['script add', { name: 'x', code: 'print(1)', url: 'https://example.com/x' }],
    ['script add', { name: 'x', code: ' ' }],
    ['script add', { name: 'x', code: 'x'.repeat(SCRIPT_LIMIT + 1) }],
    ['script add', { name: '../x', code: 'print(1)' }],
    ['script add', { name: 'x', url: 'https://example.com/a"b' }],
    ['autoexec remove', { name: 'rejoin_heartbeat.lua' }],
    ['clone add', { name: 'Clone4', package: 'com.apengjers.v3' }],
    ['clone edit', { clone: 'Clone1' }],
    ['restart', { clones: 'Clone1,' }],
    ['restart', { clones: '' }],
    ['game', { preset: 'B', clones: 'missing' }],
    ['preset remove', { key: 'A' }],
    ['preset set', { key: 'default', name: 'x', link: 'https://www.roblox.com/games/1' }],
    ['preset set', { key: 'C', name: 'x', link: 'https://example.com/games/1' }],
  ];
  for (const [path, values] of invalid) assert.throws(() => planDevice(path, values, h.device()), path);
  assert.equal(scriptName('egg'), 'egg.lua');
  assert.equal(scriptName('hub.txt'), 'hub.txt');
});

test('autocomplete handles comma prefixes, schema and protected autoexecute files', () => {
  const h = harness();
  let list = autocomplete(h.store, 'restart', {}, { name: 'clones', value: 'Clone1, Cl' });
  assert.equal(list.length, 1); assert.equal(list[0].value, 'Clone1, 3');
  list = autocomplete(h.store, 'config set', {}, { name: 'key', value: 'webhook.' });
  assert.ok(list.some(c => c.value === 'webhook.interval'));
  assert.ok(!list.some(c => c.value === 'remote.secret'));
  list = autocomplete(h.store, 'autoexec remove', {}, { name: 'name', value: '' });
  assert.deepEqual(list.map(c => c.value), ['egg.lua']);
  list = autocomplete(h.store, 'autoexec add', {}, { name: 'name', value: '' });
  assert.deepEqual(list.map(c => c.value), ['hub.txt']);
});

test('attachment download is bounded, UTF-8 text only, Discord origin only', async () => {
  const file = { name: 'farm.lua', size: 8, url: 'https://cdn.discordapp.com/attachments/1/2/farm.lua' };
  assert.equal(await downloadScript(file, async () => new Response('print(1)')), 'print(1)');
  for (const bad of [{ ...file, name: 'x.exe' }, { ...file, size: SCRIPT_LIMIT + 1 }, { ...file, url: 'http://127.0.0.1/x' }]) await assert.rejects(downloadScript(bad));
  for (const content of [Buffer.from([0xff]), Buffer.from([0]), Buffer.from([1]), Buffer.alloc(SCRIPT_LIMIT + 1, 65)]) {
    await assert.rejects(downloadScript(file, async () => new Response(content)));
  }
  await assert.rejects(downloadScript(file, async () => new Response('x', { headers: { 'content-length': String(SCRIPT_LIMIT + 1) } })));
});

test('status formatting, secret redaction, and pagination fit Discord limits', () => {
  const h = harness();
  let pages = statusPages(h.store, h.device());
  assert.match(pages[0].embeds[0].description, /\|\|owner/);
  assert.match(pages[0].embeds[0].description, /ikut default/);
  assert.match(pages[0].embeds[0].description, /<https:\/\//);
  h.device().snapshot.settings.find(s => s.key === 'webhook.hideNames').value = false;
  assert.doesNotMatch(statusPages(h.store, h.device())[0].embeds[0].description, /\|\|/);
  const lines = localLines('config get', h.device(), {});
  assert.ok(lines.some(l => l.includes('webhook.url = diset')));
  h.device().snapshot.instances = Array.from({ length: 100 }, (_, id) => ({ ...snapshot().instances[0], id, name: `Clone${id}` }));
  pages = statusPages(h.store, h.device());
  assert.ok(pages.length > 1); assert.ok(pages.every(p => p.embeds[0].description.length <= 4096));
  assert.ok(chunks(['x'.repeat(5000)]).every(s => s.length <= 1800));
});

function handlerHarness() {
  const h = harness();
  const replies = new Replies({ store: h.store, now: h.now });
  const handler = new Handler({ store: h.store, replies, now: h.now, owners: new Set([owner]), guildId: guild });
  return { ...h, replies, handler };
}

test('owner and guild checks cover slash commands, autocomplete and buttons', async () => {
  const h = handlerHarness();
  for (const mode of ['slash', 'autocomplete', 'button']) {
    const i = interaction('restart', { clones: 'all' }, { user: { id: 'not-owner' }, isAutocomplete: () => mode === 'autocomplete', isButton: () => mode === 'button' });
    await h.handler.handle(i);
    if (mode === 'autocomplete') assert.deepEqual(i.responses, [[]]);
    else assert.equal(i.responses[0].flags, MessageFlags.Ephemeral);
  }
  const i = interaction('restart', { clones: 'all' }, { guildId: 'other' });
  await h.handler.handle(i); assert.equal(i.responses[0].flags, MessageFlags.Ephemeral);
  assert.equal(h.store.commands.size, 0); h.replies.close();
});

test('confirmation is required, single-use, bound to owner and expires', async () => {
  const h = handlerHarness();
  const i = interaction('clone remove', { clone: 'Clone1' });
  await h.handler.handle(i);
  assert.equal(h.store.commands.size, 0);
  const id = [...h.handler.sessions.keys()][0];
  const button = interaction('', {}, { isButton: () => true, customId: `confirm:${id}` });
  await h.handler.handle(button); assert.equal(h.store.commands.size, 1);
  assert.equal([...h.store.commands.values()][0].args.clone, 1);
  await h.handler.handle(button); assert.equal(h.store.commands.size, 1);
  const second = interaction('script remove', { name: 'egg' }); await h.handler.handle(second);
  const next = [...h.handler.sessions.keys()][0]; h.advance(60_000); h.handler.tick();
  const expired = interaction('', {}, { isButton: () => true, customId: `confirm:${next}` });
  await h.handler.handle(expired); assert.equal(h.store.commands.size, 1);
  h.replies.close();
});

test('all-device fanout keeps per-device validation errors and all ACK results', async () => {
  const h = handlerHarness(); const other = snapshot('RF-08'); other.presets = {}; h.store.sync(other);
  const i = interaction('game', { device: 'all', preset: 'B' });
  await h.handler.handle(i); assert.equal(i.deferPayload.flags, MessageFlags.Ephemeral);
  assert.equal(h.store.commands.size, 1);
  assert.match(i.edits.at(-1).content, /RF-08/);
  h.advance(4000); h.store.sync(snapshot());
  const c = [...h.store.commands.values()][0]; h.store.ack(ack(c));
  await Promise.all([...h.replies.groups].map(g => g.chain));
  assert.match(i.edits.at(-1).content, /✅/); assert.match(i.edits.at(-1).content, /❌/);
  h.replies.close();
});

test('refresh queues status then shows the returned snapshot with fresh pagination', async () => {
  const h = handlerHarness();
  const original = interaction('status', {}); await h.handler.handle(original);
  const id = [...h.handler.sessions.keys()][0];
  const refresh = interaction('', {}, { isButton: () => true, customId: `refresh:${id}` });
  await h.handler.handle(refresh);
  h.advance(4000); h.store.sync(snapshot());
  const c = [...h.store.commands.values()][0]; const updated = snapshot(); updated.instances[0].fps = 60;
  h.store.ack(ack(c, { data: updated }));
  await Promise.all([...h.replies.groups].map(g => g.chain));
  assert.match(refresh.edits.at(-1).embeds[0].description, /60fps/);
  h.replies.close();
});

test('a fast device ACK during the first Discord edit is retained and rendered', async () => {
  const h = handlerHarness();
  const i = interaction('restart', { clones: 'Clone1' });
  let first = true;
  i.editReply = async payload => {
    if (first) {
      first = false;
      const c = [...h.store.commands.values()][0];
      h.advance(4000); h.store.sync(snapshot());
      h.store.ack(ack(c, { message: 'ACK sangat cepat' }));
      await new Promise(resolve => setTimeout(resolve, 2));
    }
    i.edits.push(payload);
  };
  await h.handler.handle(i);
  await Promise.all([...h.replies.groups].map(g => g.chain));
  assert.match(i.edits.at(-1).content, /✅.*ACK sangat cepat/);
  assert.equal(h.store.commands.size, 0); h.replies.close();
});
