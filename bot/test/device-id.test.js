import test from 'node:test';
import assert from 'node:assert/strict';
import { validateSnapshot } from '../src/http.js';
import { deviceLines } from '../src/format.js';
import { ack, harness, snapshot } from '../test-support/fixtures.js';

const withId = (name, id) => ({ ...snapshot(name), deviceId: id });

test('a device renamed from its own menu replaces the old entry and keeps its queue', () => {
  const h = harness();
  h.advance(4000); h.store.sync(withId('RF-07', 'a'.repeat(16)));
  const queued = h.store.enqueue('RF-07', 'restart', { clones: [1] });
  // Old name still fresh: not merged yet (could be a second copy of the device).
  h.advance(30_000); h.store.sync(withId('7', 'a'.repeat(16)));
  assert.deepEqual([...h.store.devices.keys()].sort(), ['7', 'RF-07']);
  h.advance(31_000);
  const sent = h.store.sync(withId('7', 'a'.repeat(16)));
  assert.deepEqual([...h.store.devices.keys()], ['7']);
  assert.equal(sent[0].id, queued.id); assert.equal(queued.name, '7');
  h.store.ack(ack(queued, { device: '7' }));
  assert.equal(h.store.commands.size, 0);
});

test('copies sharing an id stay separate while both are online; same-name clash is flagged', () => {
  const h = harness();
  h.advance(4000); h.store.sync(withId('RF-07', 'b'.repeat(16)));
  h.store.sync(withId('RF-08', 'b'.repeat(16)));
  h.advance(30_000); h.store.sync(withId('RF-07', 'b'.repeat(16))); h.store.sync(withId('RF-08', 'b'.repeat(16)));
  assert.equal(h.store.devices.size, 2);
  h.advance(5000); h.store.sync(withId('RF-07', 'c'.repeat(16)));
  assert.match(deviceLines(h.store).join('\n'), /2 device pakai nama ini/);
  assert.throws(() => validateSnapshot({ ...snapshot(), deviceId: 'not hex!' }), /invalid_device_id/);
  assert.equal(validateSnapshot(snapshot()).deviceId, undefined);
});
