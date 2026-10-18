import test from 'node:test';
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { createApi, JSON_LIMIT, PNG_LIMIT } from '../src/http.js';
import { ack, harness, png, snapshot } from '../test-support/fixtures.js';

const secret = 'a'.repeat(40);
async function api(t) {
  const h = harness();
  const logs = [];
  const server = createApi({ store: h.store, secret, now: h.now, log: line => logs.push(line) });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const url = `http://127.0.0.1:${server.address().port}`;
  const send = (path, value, headers = {}) => fetch(url + path, {
    method: 'POST', headers: { authorization: `Bearer ${secret}`, 'content-type': 'application/json', ...headers },
    body: typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value),
  });
  return { ...h, url, send, logs };
}

test('HTTP protocol round trip and unknown ACK response', async t => {
  const h = await api(t); h.advance(4000);
  const c = h.store.enqueue('RF-07', 'restart', { clones: [1, 3] });
  const sync = await h.send('/api/sync', snapshot());
  assert.equal(sync.status, 200);
  assert.deepEqual(await sync.json(), { commands: [{ id: c.id, type: 'restart', args: { clones: [1, 3] } }] });
  assert.deepEqual(await (await h.send('/api/ack', ack(c))).json(), { ok: true });
  assert.equal((await h.send('/api/ack', ack(c))).status, 200);
  const health = await (await fetch(h.url + '/health')).json();
  assert.deepEqual(health, { ok: true, devices: 1 });
  assert.equal(JSON.stringify(h.logs).includes('private'), false);
  assert.equal(JSON.stringify(h.logs).includes(secret), false);
});

test('auth failures limited per IP; valid sync/ACK/upload bypass that bucket', async t => {
  const h = await api(t);
  for (let i = 0; i < 60; i++) {
    const res = await h.send('/api/sync', snapshot(), { authorization: i % 2 ? '' : 'Bearer wrong' });
    assert.equal(res.status, 401); assert.deepEqual(await res.json(), { error: 'unauthorized' });
  }
  assert.equal((await h.send('/api/ack', {}, { authorization: 'Bearer bad' })).status, 429);
  // More than 60 distinct devices behind one IP, even after failed-auth throttling.
  for (let i = 0; i < 65; i++) assert.equal((await h.send('/api/sync', snapshot(`RF-${i + 100}`))).status, 200);
  h.advance(4000);
  const c = h.store.enqueue('RF-07', 'screenshot');
  assert.equal((await h.send('/api/sync', snapshot())).status, 200);
  assert.equal((await h.send('/api/sync', snapshot())).status, 429);
  assert.equal((await h.send(`/api/upload/${c.id}`, png, { 'content-type': 'image/png' })).status, 200);
  assert.equal((await h.send('/api/ack', ack(c, { data: { uploaded: true } }))).status, 200);
  for (let i = 0; i < 65; i++) assert.equal((await h.send('/api/ack', ack(c))).status, 200);
  h.advance(5000); assert.equal((await h.send('/api/sync', snapshot())).status, 200);
  h.advance(60_000); assert.equal((await h.send('/api/sync', snapshot(), { authorization: '' })).status, 401);
});

test('bad JSON, protocol, fields, media type, method and unknown route', async t => {
  const h = await api(t);
  for (const payload of ['{', 'null', '[]', '{}', JSON.stringify({ ...snapshot(), protocol: 2 }), JSON.stringify({ ...snapshot(), settings: {} })]) {
    assert.equal((await h.send('/api/sync', payload)).status, 400);
  }
  assert.equal((await h.send('/api/sync', snapshot(), { 'content-type': 'text/plain' })).status, 415);
  assert.equal((await fetch(h.url + '/api/sync', { headers: { authorization: `Bearer ${secret}` } })).status, 405);
  assert.equal((await fetch(h.url + '/unknown')).status, 404);
  assert.equal((await h.send('/api/ack', { protocol: 1, device: 'RF-07', id: 'c_x', ok: 'yes', message: '' })).status, 400);
});

test('JSON and PNG limits, upload restricted to sent screenshots, PNG validation', async t => {
  const h = await api(t);
  assert.equal((await h.send('/api/sync', Buffer.alloc(JSON_LIMIT + 1, 32))).status, 413);
  const status = h.store.enqueue('RF-07', 'status');
  const shot = h.store.enqueue('RF-07', 'screenshot');
  assert.equal((await h.send(`/api/upload/${shot.id}`, png, { 'content-type': 'image/png' })).status, 404);
  h.advance(4000); h.store.sync(snapshot());
  assert.equal((await h.send(`/api/upload/${status.id}`, png, { 'content-type': 'image/png' })).status, 404);
  assert.equal((await h.send(`/api/upload/${shot.id}`, Buffer.alloc(PNG_LIMIT + 1), { 'content-type': 'image/png' })).status, 413);
  assert.equal((await h.send(`/api/upload/${shot.id}`, Buffer.alloc(20), { 'content-type': 'image/png' })).status, 400);
  assert.equal((await h.send(`/api/upload/${shot.id}`, png, { 'content-type': 'image/png' })).status, 200);
});

test('chunked oversized input returns 413 instead of resetting socket', async t => {
  const h = await api(t);
  const code = await new Promise((resolve, reject) => {
    const req = request(h.url + '/api/sync', { method: 'POST', headers: { authorization: `Bearer ${secret}`, 'content-type': 'application/json' } }, res => {
      res.resume(); res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.write(Buffer.alloc(JSON_LIMIT, 32));
    req.end(Buffer.alloc(10, 32));
  });
  assert.equal(code, 413);
});
