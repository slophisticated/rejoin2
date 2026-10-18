export const mentions = { parse: [] };
export const escape = value => String(value ?? '').replace(/[\\*_`~|<>\[\]]/g, '\\$&').replace(/@/g, '@\u200b');
export const safeName = value => String(value).replace(/[^A-Za-z0-9_.-]/g, '_').slice(0, 80) || 'device';
const icons = { ingame: '🟢', starting: '🟡', recovery: '🟡', nologin: '⚪', kicked: '🔴', freeze: '🔴', stuck: '🔴', offline: '🔴', unknown: '❔' };

export function chunks(lines, limit = 1800) {
  const pages = [];
  let current = '';
  for (const original of lines) {
    // Splitting also handles a single unusually long device message.
    for (let offset = 0; offset < original.length || (offset === 0 && !original); offset += limit) {
      const line = original.slice(offset, offset + limit);
      if (current.length + line.length + 1 > limit) { pages.push(current); current = ''; }
      current += `${current ? '\n' : ''}${line}`;
    }
  }
  if (current) pages.push(current);
  return pages.length ? pages : ['Belum ada data.'];
}

export function age(store, d) { return `${Math.max(0, Math.floor((store.now() - d.lastSeen) / 1000))} dtk lalu`; }

export function deviceLines(store) {
  return [...store.devices.values()].map(d => `${store.online(d) ? '🟢' : '🔴'} **${escape(d.name)}** · v ${escape(d.snapshot.version)} · ${store.online(d) ? 'online' : 'offline'} (${age(store, d)}) · ${d.snapshot.instances.filter(i => i.status === 'ingame').length}/${d.snapshot.instances.length} clone ingame`);
}

export function statusPages(store, d) {
  const snap = d.snapshot;
  const hide = snap.settings.find(s => s.key === 'webhook.hideNames')?.value !== false;
  const defaultName = snap.presets[snap.defaultPreset]?.name || 'belum diset';
  const header = `Default: [${escape(snap.defaultPreset || '-')}] ${escape(defaultName)}`;
  const rows = snap.instances.map(i => {
    const username = i.username ? (hide ? `||${escape(i.username)}||` : escape(i.username)) : '';
    const source = { default: 'ikut default', khusus: 'khusus', link: 'link sendiri', none: 'belum ada link' }[i.presetSource] || i.presetSource;
    const stats = [Number.isFinite(i.fps) ? `${i.fps}fps` : '', Number.isFinite(i.mem) ? `${i.mem}MB` : ''].filter(Boolean).join(' ');
    const link = typeof i.link === 'string' && /^(https:\/\/|roblox:\/\/)/.test(i.link) ? ` · link: <${i.link.replace(/[<>\r\n]/g, '')}>` : '';
    return `${icons[i.status] || '❔'} ${escape(i.name)}${username ? ` · ${username}` : ''}${stats ? ` · ${stats}` : ''}\n   [${escape(i.preset || '-')}] ${escape(i.game || '-')} (${escape(source)})${link}`;
  });
  return chunks(rows.length ? rows : ['Belum ada clone.'], 3400).map((description, i, pages) => ({ embeds: [{
    title: `📊 ${d.name} — v ${snap.version} — ${store.online(d) ? 'online' : 'offline'} (${age(store, d)})`.slice(0, 256),
    description: `${header}\n\n${description}`, color: store.online(d) ? 0x2ecc71 : 0xe74c3c,
    footer: { text: `${i + 1}/${pages.length} · snapshot terakhir` },
  }] }));
}

export function localLines(path, d, values) {
  const snap = d.snapshot;
  const header = `**${escape(d.name)}**`;
  if (path === 'preset list') return [header, `Default: ${escape(snap.defaultPreset || '-')}`, ...Object.entries(snap.presets).map(([k, p]) => `[${escape(k)}] ${escape(p.name)} · <${String(p.link).replace(/[<>\r\n]/g, '')}>`)];
  if (path === 'clone list') return [header, ...snap.instances.map(i => `${escape(i.name)} · id ${escape(i.id)} · ${escape(i.package)} · [${escape(i.preset || '-')}] ${escape(i.presetSource)} · ${icons[i.status] || '❔'} ${escape(i.status)}`)];
  if (path === 'config get') {
    const settings = values.key ? snap.settings.filter(s => s.key === values.key) : snap.settings;
    if (values.key && !settings.length) throw new Error('Setting itu tidak ada di schema device.');
    return [header, ...settings.map(s => `${escape(s.key)} = ${s.secret ? (s.value ? 'diset' : 'kosong') : escape(s.value)} · ${escape(s.label || s.key)}${s.type === 'int' ? ` (${s.min ?? '-'}–${s.max ?? '-'})` : ''}`)];
  }
  const auto = snap.autoexecute || [];
  if (path === 'autoexec list') return [header, '**Autoexecute**', ...(auto.length ? auto.map(s => `${s.managed ? '🔒' : '⚡'} ${escape(s.name)} · ${s.size} byte${s.fromScripts ? ' · dari Scripts' : ''}`) : ['Kosong.'])];
  if (path === 'script list') return [header, '**Scripts**', ...(snap.scripts.length ? snap.scripts.map(s => `${s.auto ? '⚡' : '•'} ${escape(s.name)} · ${s.size} byte`) : ['Kosong.']), '**Autoexecute**', ...(auto.length ? auto.map(s => `${s.managed ? '🔒' : '⚡'} ${escape(s.name)} · ${s.size} byte`) : ['Kosong.'])];
  throw new Error('Tampilan tidak dikenal.');
}

export function resultLine(item) {
  const label = `${escape(item.command?.device || item.device)}${item.command ? ` · ${escape(item.command.args.key || item.command.type)}` : ''}`;
  if (item.error) return `❌ ${label}: ${escape(item.error).slice(0, 450)}`;
  if (item.result) {
    let msg = item.result.message || (item.result.ok ? 'Selesai.' : 'Gagal.');
    const c = item.command;
    if (c?.type === 'config_set' && (c.args.key === 'webhook.url' || item.secret)) msg = item.result.ok ? `${c.args.key}: ${c.args.value ? 'diset' : 'dikosongkan'}` : 'Setting rahasia gagal diubah; cek format nilainya.';
    return `${item.result.ok ? '✅' : '❌'} ${label}: ${escape(msg).slice(0, 450)}`;
  }
  if (item.command?.timedOut) return `⌛ ${label}: belum merespons (device offline / monitor tidak jalan). Command tetap antri.`;
  return `⏳ ${label}: nunggu device (sync tiap ±${item.interval} dtk)${item.offline ? ' · offline, dijalankan saat monitor online lagi' : ''}.`;
}
