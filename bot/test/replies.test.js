import test from 'node:test';
import assert from 'node:assert/strict';
import { MessageFlags } from 'discord.js';
import { Replies } from '../src/replies.js';
import { ack, harness, interaction, png, snapshot } from '../test-support/fixtures.js';

test('concurrent ACK edits serialize; summary retains every command result and timeout', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now });
  const i = interaction();
  let active = 0, maximum = 0;
  i.editReply = async payload => { active++; maximum = Math.max(maximum, active); await new Promise(r => setTimeout(r, 2)); i.edits.push(payload); active--; };
  const commands = ['status', 'config_set', 'restart'].map(type => h.store.enqueue('RF-07', type, {}));
  const g = replies.create(i, commands.map(command => ({ command, interval: 30 })));
  h.advance(4000); h.store.sync(snapshot());
  h.store.ack(ack(commands[0], { message: 'first' })); h.store.ack(ack(commands[1], { message: 'second' }));
  h.advance(90_000); h.store.tick(); await g.chain;
  assert.equal(maximum, 1); assert.match(i.edits.at(-1).content, /first/); assert.match(i.edits.at(-1).content, /second/); assert.match(i.edits.at(-1).content, /tetap antri/);
  h.store.ack(ack(commands[2], { message: 'third' })); await g.chain;
  assert.match(i.edits.at(-1).content, /third/); replies.close();
});

test('screenshot all sends at most ten files per reply and only ephemeral followups', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now }); const i = interaction();
  const items = [];
  for (let n = 0; n < 12; n++) {
    const name = `device-${n}`; h.store.sync(snapshot(name));
    items.push({ command: h.store.enqueue(name, 'screenshot'), interval: 30 });
  }
  const g = replies.create(i, items);
  h.advance(4000);
  for (const item of items) {
    h.store.sync(snapshot(item.command.device)); h.store.upload(item.command.id, png);
    h.store.ack(ack(item.command, { data: { uploaded: true } }));
  }
  await g.chain;
  const messages = [...i.edits, ...i.follows].filter(p => p.files);
  assert.equal(messages.reduce((n, p) => n + p.files.length, 0), 12);
  assert.ok(messages.every(p => p.files.length <= 10));
  assert.ok(i.follows.every(p => p.flags === MessageFlags.Ephemeral));
  assert.equal(h.store.uploads.size, 0); assert.ok(items.every(x => !x.result.buffer)); replies.close();
});

test('script view attaches content, secret setting ACK never echoes webhook URL', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now });
  const i = interaction(); const c = h.store.enqueue('RF-07', 'script_get', { name: 'egg.lua' });
  const g = replies.create(i, [{ command: c, interval: 30 }]); h.advance(4000); h.store.sync(snapshot());
  h.store.ack(ack(c, { data: { name: 'egg.lua', content: 'print("secret-script")' } })); await g.chain;
  assert.equal(i.edits.at(-1).files[0].name, 'egg.lua');
  assert.equal(i.edits.at(-1).files[0].attachment.toString(), 'print("secret-script")');
  assert.doesNotMatch(i.edits.at(-1).content, /secret-script/);
  const hook = h.store.enqueue('RF-07', 'config_set', { key: 'webhook.url', value: 'https://discord.com/api/webhooks/1/secret-token' });
  const hookReply = interaction(); const other = replies.create(hookReply, [{ command: hook, secret: true, interval: 30 }]);
  h.advance(4000); h.store.sync(snapshot()); h.store.ack(ack(hook, { message: hook.args.value })); await other.chain;
  assert.match(hookReply.edits.at(-1).content, /diset/); assert.doesNotMatch(JSON.stringify(hookReply.edits), /secret-token/);
  replies.close();
});

test('expired interaction accepts ACK without editing or keeping screenshot buffer', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now }); const i = interaction();
  const c = h.store.enqueue('RF-07', 'screenshot'); const g = replies.create(i, [{ command: c, interval: 30 }]); await g.chain;
  h.advance(4000); h.store.sync(snapshot());
  h.advance(900_000); replies.tick(); const count = i.edits.length;
  h.store.upload(c.id, png); h.store.ack(ack(c, { data: { uploaded: true } })); await g.chain;
  assert.equal(i.edits.length, count); assert.equal(h.store.uploads.size, 0); assert.equal(replies.byCommand.size, 0); replies.close();
});

test('failed Discord send drops screenshot after five minutes', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now }); const i = interaction();
  i.editReply = async () => { throw new Error('mock disconnect'); };
  const c = h.store.enqueue('RF-07', 'screenshot'); const item = { command: c, interval: 30 };
  const g = replies.create(i, [item]); h.advance(4000); h.store.sync(snapshot()); h.store.upload(c.id, png);
  h.store.ack(ack(c, { data: { uploaded: true } })); await g.chain;
  assert.ok(item.result.buffer); h.advance(300_000); replies.tick(); await g.chain;
  assert.equal(item.result.buffer, undefined); assert.equal(item.result.ok, false); replies.close();
});

test('transient Discord edit failure retries without another ACK', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now }); const i = interaction();
  let calls = 0;
  i.editReply = async payload => { calls++; if (calls === 1) throw new Error('temporary'); i.edits.push(payload); };
  const c = h.store.enqueue('RF-07', 'status'); const g = replies.create(i, [{ command: c, interval: 30 }]);
  h.advance(4000); h.store.sync(snapshot()); h.store.ack(ack(c)); await g.chain;
  // A failure on the initial edit is retried by the already queued ACK update.
  assert.match(i.edits.at(-1).content, /✅/);
  const j = interaction(); let disconnected = true;
  j.editReply = async payload => { if (disconnected) throw new Error('temporary'); j.edits.push(payload); };
  const next = h.store.enqueue('RF-07', 'restart', { clones: [1] });
  const second = replies.create(j, [{ command: next, interval: 30 }]); await second.chain;
  h.advance(4000); h.store.sync(snapshot()); h.store.ack(ack(next)); await second.chain;
  assert.equal(j.edits.length, 0); disconnected = false;
  h.advance(30_000); replies.tick(); await second.chain;
  assert.match(j.edits.at(-1).content, /✅/); replies.close();
});

test('/report: the device report arrives as a text file', async () => {
  const h = harness(); const replies = new Replies({ store: h.store, now: h.now });
  const i = interaction(); const c = h.store.enqueue('RF-07', 'report');
  const g = replies.create(i, [{ command: c, interval: 30 }]); h.advance(4000); h.store.sync(snapshot());
  h.store.ack(ack(c, { message: 'report terlampir', data: { name: 'rejoin-report-RF-07.txt', content: '===== Rejoin report =====' } }));
  await g.chain;
  assert.equal(i.edits.at(-1).files[0].name, 'rejoin-report-RF-07.txt');
  assert.match(i.edits.at(-1).files[0].attachment.toString(), /Rejoin report/);
  replies.close();
});
