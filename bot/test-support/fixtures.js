import { Store } from '../src/store.js';

export function snapshot(device = 'RF-07') {
  return {
    protocol: 1, device, version: 'abc1234', time: 1760780000,
    presets: { A: { name: 'Steal an Egg', link: 'https://www.roblox.com/games/1' }, B: { name: 'Fisch', link: 'https://www.roblox.com/share?code=private&type=Server' } },
    defaultPreset: 'A',
    instances: [
      { id: 1, name: 'Clone1', package: 'com.apengjers.v3', preset: 'A', presetSource: 'default', game: 'Steal an Egg', link: 'https://www.roblox.com/games/1', status: 'ingame', username: 'owner_one', fps: 15, mem: 420 },
      { id: 3, name: 'Clone3', package: 'com.apengjers.v5', preset: 'B', presetSource: 'khusus', game: 'Fisch', link: 'https://www.roblox.com/games/2', status: 'starting' },
    ],
    scripts: [{ name: 'egg.lua', size: 12, auto: true }, { name: 'hub.txt', size: 9, auto: false }],
    autoexecute: [{ name: 'egg.lua', size: 12, fromScripts: true, managed: false }, { name: 'rejoin_heartbeat.lua', size: 90, fromScripts: false, managed: true }],
    settings: [
      { key: 'launchJoinTimeout', type: 'int', min: 0, max: 1800, value: 240 },
      { key: 'launchSettleDelay', type: 'int', min: 0, max: 600, value: 20 },
      { key: 'launchEmptyDelay', type: 'int', min: 0, max: 120, value: 5 },
      { key: 'windowLayout.enabled', type: 'bool', value: false },
      { key: 'windowLayout.columns', type: 'int', min: 0, max: 10, value: 0 },
      { key: 'windowLayout.gap', type: 'int', min: 0, max: 200, value: 0 },
      { key: 'windowLayout.overlap', type: 'int', min: 0, max: 400, value: 80 },
      { key: 'heartbeat.enabled', type: 'bool', value: true },
      { key: 'heartbeat.saver.enabled', type: 'bool', value: false },
      { key: 'heartbeat.saver.fpsCap', type: 'int', min: 0, max: 240, value: 15 },
      { key: 'heartbeat.saver.disable3d', type: 'bool', value: true },
      { key: 'webhook.url', type: 'string', max: 300, secret: true, value: 'set' },
      { key: 'webhook.interval', type: 'int', min: 60, max: 3600, value: 300 },
      { key: 'webhook.screenshot', type: 'bool', value: true },
      { key: 'webhook.events', type: 'bool', value: true },
      { key: 'webhook.hideNames', type: 'bool', value: true },
      { key: 'webhook.deviceName', type: 'string', max: 60, value: device },
      { key: 'remote.interval', type: 'int', min: 10, max: 600, value: 30 },
    ],
  };
}

export function harness(options = {}) {
  let time = 1_000_000;
  const now = () => time;
  const store = new Store({ ...options, now });
  store.sync(snapshot());
  return { store, now, advance: ms => { time += ms; }, device: () => store.devices.get('RF-07') };
}

export const ack = (c, extra = {}) => ({ protocol: 1, device: c.device, id: c.id, ok: true, message: 'Berhasil', data: null, ...extra });
export const png = Buffer.from('89504e470d0a1a0a0000000049454e44ae426082', 'hex');
export const owner = '12345678901234567';
export const guild = '23456789012345678';

export function interaction(path = 'restart', values = { clones: 'Clone1' }, overrides = {}) {
  const [commandName, sub = null] = path.split(' ');
  const edits = [], follows = [], updates = [], responses = [];
  const options = { getSubcommand: () => sub, getFocused: () => ({ name: 'device', value: '' }) };
  for (const kind of ['String', 'Integer', 'Boolean', 'Attachment']) options[`get${kind}`] = name => values[name] ?? null;
  const i = {
    user: { id: owner }, guildId: guild, commandName, options, createdTimestamp: 1_000_000,
    attachmentSizeLimit: 8 * 1024 * 1024, edits, follows, updates, responses,
    isAutocomplete: () => false, isButton: () => false, isChatInputCommand: () => true,
    async deferReply(payload) { i.deferred = true; i.deferPayload = payload; },
    async deferUpdate() { i.deferred = true; },
    async editReply(payload) { edits.push(payload); return { id: 'original' }; },
    async reply(payload) { i.replied = true; responses.push(payload); },
    async respond(payload) { responses.push(payload); },
    async followUp(payload) { follows.push(payload); return { id: `follow-${follows.length}` }; },
    async update(payload) { updates.push(payload); },
    webhook: { async editMessage(id, payload) { updates.push({ id, ...payload }); }, async deleteMessage() {} },
    ...overrides,
  };
  return i;
}
