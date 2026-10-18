import { routes } from './definitions.js';

const choice = (name, value) => ({ name: String(name).slice(0, 100), value: String(value) });

export function autocomplete(store, path, values, focused) {
  const query = String(focused.value || '').toLowerCase();
  if (focused.name === 'device') {
    const devices = [...store.devices.values()].map(d => choice(`${d.name} · ${store.online(d) ? 'online' : 'offline'}`, d.name));
    if (routes[path]?.all && devices.length) devices.unshift(choice('all — semua device', 'all'));
    return devices.filter(x => x.value.length <= 100 && x.name.toLowerCase().includes(query)).slice(0, 25);
  }
  const devices = values.device === 'all' && routes[path]?.all ? [...store.devices.values()]
    : values.device ? [store.devices.get(values.device)].filter(Boolean)
      : store.devices.size === 1 ? [...store.devices.values()] : [];
  if (!devices.length) return [];
  const d = devices[0];
  let list = [];
  if (focused.name === 'preset' || (focused.name === 'key' && path.startsWith('preset'))) {
    list = Object.entries(d.snapshot.presets).filter(([k]) => devices.every(x => Object.hasOwn(x.snapshot.presets, k)))
      .map(([k, p]) => choice(`${k} — ${p.name}`, k));
    if (path === 'clone edit' || path === 'clone add') list.unshift(choice('default — ikut default', 'default'), choice('- — link sendiri', '-'));
  } else if (focused.name === 'key') {
    list = d.snapshot.settings.filter(s => devices.every(x => x.snapshot.settings.some(t => t.key === s.key)))
      .map(s => choice(`${s.key} — ${s.label || s.type}`, s.key));
  } else if (focused.name === 'clone' || focused.name === 'clones') {
    const parts = String(focused.value || '').split(',');
    const prefix = focused.name === 'clones' ? parts.slice(0, -1).map(x => x.trim()) : [];
    const tail = parts.at(-1).trim().toLowerCase();
    const used = new Set(prefix.flatMap(ref => d.snapshot.instances.filter(i => String(i.id) === ref || i.name === ref || i.package === ref).map(i => i.id)));
    list = d.snapshot.instances.filter(i => !used.has(i.id))
      .filter(i => `${i.name} ${i.username || ''} ${i.package} ${i.id}`.toLowerCase().includes(tail))
      .map(i => choice(`${i.name} — ${i.username || '-'} — ${i.status}`, [...prefix, String(i.id)].join(', ')));
    if (focused.name === 'clones' && !prefix.length) list.unshift(choice('all — semua clone', 'all'));
    return list.filter(c => c.value.length <= 100).slice(0, 25);
  } else if (focused.name === 'name' && (path.startsWith('script') || path.startsWith('autoexec'))) {
    const remove = path === 'autoexec remove';
    list = (remove ? d.snapshot.autoexecute : d.snapshot.scripts)
      .filter(s => !remove || (!s.managed && s.name !== 'rejoin_heartbeat.lua'))
      .filter(s => path !== 'autoexec add' || (!s.auto && s.name !== 'rejoin_heartbeat.lua'))
      .filter(s => path !== 'script remove' || s.name !== 'rejoin_heartbeat.lua')
      .filter(s => devices.every(x => (remove ? x.snapshot.autoexecute : x.snapshot.scripts).some(t => t.name === s.name && (!remove || !t.managed))))
      .map(s => choice(s.name, s.name));
  }
  return list.filter(c => c.value.length <= 100 && c.name.toLowerCase().includes(query)).slice(0, 25);
}
