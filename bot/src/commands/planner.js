import { routes } from './definitions.js';
import { cloneRefs, configValue, findClone, gameLink, loaderUrl, present, presetExists, scriptContent, scriptName, text } from './validate.js';

const shortcuts = {
  'webhook options': { interval: 'webhook.interval', screenshot: 'webhook.screenshot', notif_key: 'webhook.events', hide_names: 'webhook.hideNames' },
  window: { enabled: 'windowLayout.enabled', columns: 'windowLayout.columns', gap: 'windowLayout.gap', overlap: 'windowLayout.overlap' },
  saver: { heartbeat: 'heartbeat.enabled', enabled: 'heartbeat.saver.enabled', fps_cap: 'heartbeat.saver.fpsCap', disable3d: 'heartbeat.saver.disable3d' },
  launch: { join_timeout: 'launchJoinTimeout', settle: 'launchSettleDelay', empty: 'launchEmptyDelay' },
};

export function selectDevices(store, path, requested) {
  if (requested === 'all') {
    if (!routes[path]?.all) throw new Error('Command ini tidak mendukung device all.');
    if (!store.devices.size) throw new Error('Belum ada device. Jalankan monitor dan cek secret/URL bot.');
    return [...store.devices.values()];
  }
  if (!requested) {
    if (store.devices.size === 1) return [...store.devices.values()];
    throw new Error(store.devices.size ? 'Ada beberapa device; isi opsi device dulu.' : 'Belum ada device. Jalankan monitor dan cek secret/URL bot.');
  }
  const d = store.devices.get(requested);
  if (!d) throw new Error('Device tidak ditemukan. Cek /devices.');
  return [d];
}

function requireScript(device, name, auto = false) {
  if (!(auto ? device.snapshot.autoexecute : device.snapshot.scripts).some(s => s.name === name)) throw new Error(`Script ${name} tidak ditemukan.`);
}

export function planDevice(path, v, device) {
  const cmd = (type, args = {}) => [{ type, args }];
  const set = (key, value) => ({ type: 'config_set', args: { key, value: configValue(device, key, value) } });
  if (shortcuts[path]) {
    const commands = Object.entries(shortcuts[path]).filter(([o]) => present(v[o])).map(([o, key]) => set(key, v[o]));
    if (!commands.length) throw new Error('Isi minimal satu opsi setting.');
    return commands;
  }
  switch (path) {
    case 'status': return cmd('status');
    case 'game': case 'default': {
      const args = { preset: presetExists(device, v.preset), rejoin: v.rejoin ?? true };
      if (present(v.clones)) args.clones = cloneRefs(device, v.clones);
      return cmd(path === 'game' ? 'game' : 'default_set', args);
    }
    case 'preset set': {
      if (!/^[A-Za-z0-9_]{1,16}$/.test(v.key) || v.key === 'default') throw new Error('Kode preset: huruf/angka/_, 1–16 karakter, bukan default.');
      return cmd('preset_set', { key: v.key, name: text(v.name, 'Nama preset', 60), link: gameLink(v.link), rejoin: v.rejoin ?? false });
    }
    case 'preset remove':
      presetExists(device, v.key);
      if (device.snapshot.defaultPreset === v.key) throw new Error('Preset itu DEFAULT; ganti default dulu.');
      return cmd('preset_remove', { key: v.key });
    case 'clone add': case 'clone edit': {
      const edit = path === 'clone edit';
      const current = edit ? findClone(device, v.clone) : null;
      const args = edit ? { clone: current.id } : {};
      if (edit && !['name', 'package', 'preset', 'link'].some(k => present(v[k]))) throw new Error('Isi minimal satu perubahan clone.');
      if (present(v.name)) args.name = text(v.name, 'Nama clone', 40);
      if (present(v.package)) {
        if (!/^[A-Za-z0-9_]+\.[A-Za-z0-9_.]+$/.test(v.package)) throw new Error('Package tidak valid (mis. com.apengjers.v7).');
        if (device.snapshot.instances.some(i => i.package === v.package && i.id !== current?.id)) throw new Error('Package sudah terdaftar.');
        args.package = text(v.package, 'Package', 300);
      }
      if (present(v.preset)) {
        args.preset = ['', 'default', '-'].includes(v.preset) ? v.preset : presetExists(device, v.preset);
      }
      if (present(v.link)) args.link = edit && ['', '-'].includes(v.link) ? v.link : gameLink(v.link);
      if (args.preset === '-' && !(present(args.link) ? !['', '-'].includes(args.link) : current?.link)) throw new Error('Preset - butuh link sendiri.');
      return cmd(edit ? 'instance_edit' : 'instance_add', args);
    }
    case 'clone remove': return cmd('instance_remove', { clone: findClone(device, v.clone).id });
    case 'clone logout': {
      const refs = cloneRefs(device, v.clones, false);
      return cmd('logout', { clones: refs });
    }
    case 'cookie inject': return cmd('cookie_inject', { clone: findClone(device, v.clone).id });
    case 'alarm set': {
      const current = findClone(device, v.clone);
      if (!/^(\d{2})\/(\d{2})(?:\/(\d{4}))?$/.test(String(v.date || ''))) throw new Error('Tanggal harus format DD/MM atau DD/MM/YYYY.');
      const [, dayText, monthText, yearText] = v.date.match(/^(\d{2})\/(\d{2})(?:\/(\d{4}))?$/);
      const day = Number(dayText), month = Number(monthText), year = yearText ? Number(yearText) : 2024;
      const monthDays = [31, year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      if (month < 1 || month > 12 || day < 1 || day > monthDays[month - 1]) throw new Error('Tanggal kalender tidak valid.');
      if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(v.time || ''))) throw new Error('Waktu harus format HH:MM WIB, misalnya 12:00.');
      return cmd('logout_alarm_set', { clone: current.id, date: v.date, time: v.time, daily: v.daily === true });
    }
    case 'alarm remove': return cmd('logout_alarm_remove', { clone: findClone(device, v.clone).id });
    case 'restart': {
      const refs = cloneRefs(device, v.clones);
      return refs === 'all' ? cmd('launch_all') : cmd('restart', { clones: refs });
    }
    case 'screenshot': return cmd('screenshot');
    case 'report': return cmd('report');
    case 'config set': return [set(v.key, v.value)];
    case 'webhook set': return [set('webhook.url', v.url)];
    case 'webhook test': return cmd('webhook_test');
    case 'device rename': return cmd('device_rename', { name: text(v.name.trim(), 'Nama device', 60) });
    case 'device replace':
      if (!/^(?:\d{17,20}|https:\/\/(?:(?:canary|ptb)\.)?discord(?:app)?\.com\/channels\/\d+\/\d+\/\d+)$/.test(v.message_link)) throw new Error('Isi link pesan Discord atau ID pesan yang valid.');
      return cmd('webhook_use_message', { link: v.message_link });
    case 'script add': {
      const name = scriptName(v.name, { protectedName: true });
      if ([v.file, v.url, v.code].filter(present).length !== 1) throw new Error('Isi tepat satu: file, url, atau code.');
      return cmd('script_add', present(v.url) ? { name, url: loaderUrl(v.url) } : { name, content: scriptContent(v.content ?? v.code) });
    }
    case 'script view': case 'script remove': {
      const name = scriptName(v.name, { protectedName: path.endsWith('remove') });
      requireScript(device, name);
      return cmd(path.endsWith('view') ? 'script_get' : 'script_remove', { name });
    }
    case 'autoexec add': case 'autoexec remove': {
      const name = scriptName(v.name, { protectedName: true });
      const remove = path.endsWith('remove');
      requireScript(device, name, remove);
      if (remove && device.snapshot.autoexecute.find(s => s.name === name)?.managed) throw new Error('Script ini diatur Rejoin.');
      return cmd(remove ? 'auto_remove' : 'auto_add', { name, rejoin: v.rejoin ?? false });
    }
    default: throw new Error('Command tidak dikenal.');
  }
}
