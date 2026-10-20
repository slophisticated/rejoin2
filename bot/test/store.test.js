import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store } from '../src/store.js';
import { ack, harness, png, snapshot } from '../test-support/fixtures.js';

test('FIFO, resend exactly once after 60s, no repeat restart/launch_all', () => {
  const h = harness();
  const a = h.store.enqueue('RF-07', 'config_set', { key: 'remote.interval', value: 30 });
  const b = h.store.enqueue('RF-07', 'restart', { clones: [1] });
  const c = h.store.enqueue('RF-07', 'launch_all');
  // Queued commands skip the 4s sync limit (the device syncs right after a long poll).
  assert.deepEqual(h.store.sync(snapshot()).map(c => c.id), [a.id, b.id, c.id]);
  assert.equal(h.store.sync(snapshot()), null);
  h.advance(4000);
  assert.deepEqual(h.store.sync(snapshot()), []);
  h.advance(56_000);
  assert.deepEqual(h.store.sync(snapshot()), []);
  h.advance(4001);
  assert.deepEqual(h.store.sync(snapshot()).map(c => c.id), [a.id]);
  h.advance(70_000);
  assert.deepEqual(h.store.sync(snapshot()), []);
});

test('timeout keeps queued command; late ACK finishes once; wrong device ignored', () => {
  const h = harness();
  let timeouts = 0, results = 0;
  h.store.on('timeout', () => timeouts++);
  h.store.on('result', () => results++);
  const c = h.store.enqueue('RF-07', 'status');
  h.store.ack(ack(c));
  assert.equal(h.store.commands.size, 1);
  h.advance(90_000); h.store.tick(); h.store.tick();
  assert.equal(timeouts, 1);
  assert.equal(h.store.online('RF-07'), true);
  h.advance(1);
  assert.equal(h.store.online('RF-07'), false);
  assert.equal(h.store.sync(snapshot()).length, 1);
  h.store.ack(ack(c, { device: 'other' }));
  assert.equal(h.store.commands.size, 1);
  h.store.ack(ack(c)); h.store.ack(ack(c));
  assert.equal(h.store.commands.size, 0);
  assert.equal(results, 1);
});

test('sensitive cookie commands are single-delivery, transient, and scrubbed on ACK or timeout', () => {
  const h = harness({ timeoutMs: 1000 });
  const token = 'cookie-secret-value';
  const acknowledged = h.store.enqueue('RF-07', 'cookie_inject', { clone: 1, token }, { sensitive: true });
  h.advance(4000); h.store.sync(snapshot());
  h.advance(4000); const delivered = h.store.sync(snapshot());
  assert.equal(delivered.length, 0);
  h.store.ack(ack(acknowledged));
  assert.equal(acknowledged.args.token, undefined);

  const expired = h.store.enqueue('RF-07', 'cookie_inject', { clone: 1, token }, { sensitive: true });
  h.advance(1000); h.store.tick();
  assert.equal(h.store.commands.has(expired.id), false);
  assert.equal(expired.args.token, undefined);
});

for (const type of ['device_rename', 'config_set']) {
  test(`${type}: rename moves queue and accepts old ACKs for the whole old batch`, () => {
    const h = harness();
    const rename = h.store.enqueue('RF-07', type, type === 'device_rename' ? { name: 'RF-08' } : { key: 'webhook.deviceName', value: 'RF-08' });
    const first = h.store.enqueue('RF-07', 'restart', { clones: [1] });
    const second = h.store.enqueue('RF-07', 'status');
    h.advance(4000); h.store.sync(snapshot());
    const next = h.store.enqueue('RF-07', 'launch_all');
    h.store.ack(ack(rename, { device: 'RF-07' }));
    assert.equal(h.store.devices.has('RF-07'), false);
    assert.equal(h.store.devices.get('RF-08').snapshot.device, 'RF-08');
    assert.equal(next.device, 'RF-08');
    h.store.ack(ack(first, { device: 'RF-07' }));
    h.store.ack(ack(second, { device: 'RF-07', data: snapshot() }));
    assert.equal(h.store.devices.get('RF-08').snapshot.device, 'RF-08');
    assert.deepEqual([...h.store.commands.keys()], [next.id]);
    h.advance(4000);
    assert.equal(h.store.sync(snapshot('RF-08'))[0].id, next.id);
  });
}

test('rename collisions and concurrent reservations rejected before enqueue', () => {
  const h = harness(); h.store.sync(snapshot('RF-09'));
  assert.throws(() => h.store.enqueue('RF-07', 'device_rename', { name: 'RF-09' }), /dipakai/);
  h.store.enqueue('RF-07', 'device_rename', { name: 'RF-08' });
  assert.throws(() => h.store.enqueue('RF-09', 'device_rename', { name: 'RF-08' }), /dipesan/);
});

for (const uploadFirst of [true, false]) {
  test(`screenshot: ${uploadFirst ? 'upload before ACK' : 'ACK before upload'} sends buffer once`, () => {
    const h = harness();
    const c = h.store.enqueue('RF-07', 'screenshot');
    assert.equal(h.store.canUpload(c.id), false);
    h.advance(4000); h.store.sync(snapshot());
    const results = [];
    h.store.on('result', (_c, r) => results.push(r));
    const result = ack(c, { data: { uploaded: true, bytes: png.length } });
    if (uploadFirst) { h.store.upload(c.id, png); h.store.ack(result); }
    else { h.store.ack(result); assert.equal(results.length, 0); assert.equal(h.store.canUpload(c.id), true); h.store.upload(c.id, png); }
    assert.equal(results.length, 1);
    assert.deepEqual(results[0].buffer, png);
    assert.equal(h.store.commands.size, 0);
    assert.equal(h.store.uploads.size, 0);
    assert.equal(h.store.upload(c.id, png), false);
  });
}

test('screenshot upload expiry, missing upload grace, failed ACK clears buffer', () => {
  const h = harness();
  const c = h.store.enqueue('RF-07', 'screenshot');
  h.advance(4000); h.store.sync(snapshot()); h.store.upload(c.id, png);
  h.advance(300_000); h.store.tick(); assert.equal(h.store.uploads.size, 0);
  const results = []; h.store.on('result', (_c, r) => results.push(r));
  h.store.ack(ack(c, { data: { uploaded: true } }));
  h.advance(29_999); h.store.tick(); assert.equal(results.length, 0);
  h.advance(1); h.store.tick(); assert.equal(results[0].ok, false);
  const d = h.store.enqueue('RF-07', 'screenshot');
  h.advance(4000); h.store.sync(snapshot()); h.store.upload(d.id, png);
  h.store.ack(ack(d, { ok: false })); assert.equal(h.store.uploads.size, 0);
});

test('atomic persistence restores snapshots and pending commands, without upload buffers/tokens', async t => {
  const dataDir = await mkdtemp(join(tmpdir(), 'rejoin-bot-test-'));
  assert.ok(dataDir.startsWith(join(tmpdir(), 'rejoin-bot-test-')));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const h = harness({ dataDir });
  const c = h.store.enqueue('RF-07', 'status');
  const shot = h.store.enqueue('RF-07', 'screenshot');
  h.store.enqueue('RF-07', 'cookie_inject', { clone: 1, token: 'sensitive-cookie-value' }, { sensitive: true });
  h.advance(4000); h.store.sync(snapshot()); h.store.upload(shot.id, png);
  await h.store.close();
  const disk = await readFile(join(dataDir, 'state.json'), 'utf8');
  assert.equal(disk.includes('attachment'), false);
  assert.equal(disk.includes('sensitive-cookie-value'), false);
  assert.equal(disk.includes('cookie_inject'), false);
  const restored = new Store({ now: h.now, dataDir }); await restored.load();
  assert.equal(restored.devices.size, 1); assert.equal(restored.commands.has(c.id), true);
  assert.equal(restored.uploads.size, 0);
  await restored.close();
  await writeFile(join(dataDir, 'state.json'), '{bad');
  const broken = new Store({ dataDir }); await broken.load();
  assert.equal(broken.devices.size, 0);
});

test('a snapshot riding on any ACK refreshes the device at once (script add -> /script list)', () => {
  const h = harness();
  h.advance(4000);
  const c = h.store.enqueue('RF-07', 'script_add', { name: 'yanamin.lua', content: 'print(1)' });
  h.store.sync(snapshot());
  const after = snapshot(); after.scripts = [...after.scripts, { name: 'yanamin.lua', size: 117, auto: false }];
  h.store.ack(ack(c, { data: after }));
  assert.ok(h.device().snapshot.scripts.some(s => s.name === 'yanamin.lua'));
  assert.equal(h.store.commands.has(c.id), false);
});
