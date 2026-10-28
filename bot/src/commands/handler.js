import { randomUUID } from 'node:crypto';
import { ActionRowBuilder, ButtonBuilder, ButtonStyle, MessageFlags, ModalBuilder, TextInputBuilder, TextInputStyle } from 'discord.js';
import { routes, interactionPath, interactionValues } from './definitions.js';
import { autocomplete } from './autocomplete.js';
import { planDevice, selectDevices } from './planner.js';
import { downloadScript, present, setting } from './validate.js';
import { alarmImportReport, downloadAlarmCsv, parseAlarmCsv, resolveAlarmRows } from './alarm_import.js';
import { renameTarget } from '../store.js';
import { chunks, deviceLines, overviewLines, escape, localLines, mentions, statusPages } from '../format.js';

const localPaths = new Set(['preset list', 'clone list', 'config get', 'script list', 'autoexec list', 'alarm list']);
const button = (id, label, style = ButtonStyle.Secondary, disabled = false) => new ButtonBuilder().setCustomId(id).setLabel(label).setStyle(style).setDisabled(disabled);

export class Handler {
  constructor({ store, replies, owners = new Set(), accounts = null, registry = null, guildId, now = Date.now, fetcher = fetch, log = () => {} }) {
    // accounts: Discord user ID -> account; each owner only sees the devices of their account.
    accounts ??= new Map([...owners].map(id => [id, '']));
    Object.assign(this, { store, replies, accounts, registry, guildId, now, fetcher, log });
    this.sessions = new Map();
  }

  allowed(i) { return this.accounts.has(i.user.id) && i.guildId === this.guildId; }

  view(i) { return this.store.view(this.accounts.get(i.user.id)); }

  async handle(i) {
    try {
      if (!this.allowed(i)) {
        if (i.isAutocomplete()) return await i.respond([]);
        return await i.reply({ content: '❌ Kamu tidak punya akses.', flags: MessageFlags.Ephemeral, allowedMentions: mentions });
      }
      if (i.isAutocomplete()) {
        const path = interactionPath(i);
        if (!routes[path]) return await i.respond([]);
        return await i.respond(autocomplete(this.view(i), path, interactionValues(i, path), i.options.getFocused(true)));
      }
      if (i.isButton()) return await this.component(i);
      if (i.isModalSubmit()) return await (i.customId.startsWith('delta:') ? this.deltaKeyModal(i) : this.cookieModal(i));
      if (!i.isChatInputCommand()) return;
      const path = interactionPath(i);
      if (!routes[path]) throw new Error('Command tidak dikenal. Daftarkan ulang command bot.');
      const values = interactionValues(i, path);
      const view = this.view(i);
      if (path === 'cookie inject') return await this.openCookieModal(i, values, view);
      if (path === 'delta input-key') return await this.openDeltaKeyModal(i, values, view);
      await i.deferReply({ flags: MessageFlags.Ephemeral });
      if (path === 'devices') return await this.show(i, chunks(deviceLines(view)).map(content => ({ content })));
      if (path === 'hwid redeem' || path === 'hwid remove') return await this.hwid(i, path, String(values.hwid || '').trim().toLowerCase());
      if (path === 'alarm import') return await this.previewAlarmImport(i, values, view);
      // No device = every device of this account.
      if (path === 'overview') {
        const list = values.device ? selectDevices(view, path, values.device) : [...view.devices.values()];
        return await this.show(i, chunks(overviewLines(view, list)).map(content => ({ content })));
      }
      const devices = selectDevices(view, path, values.device);
      if (path === 'status') return await this.showStatus(i, devices[0]);
      if (localPaths.has(path)) return await this.show(i, chunks(localLines(path, devices[0], values)).map(content => ({ content })));
      if (path === 'script add') {
        if ([values.file, values.url, values.code].filter(present).length !== 1) throw new Error('Isi tepat satu: file, url, atau code.');
        if (values.file) values.content = await downloadScript(values.file, this.fetcher);
      }
      if (path === 'device remove' && this.store.online(devices[0])) {
        throw new Error('Device ini masih online; cuma device offline yang bisa dihapus.');
      }
      if (routes[path].confirm) {
        // Freeze the chosen clone ID and device list, rather than resolving a new target on confirmation.
        if (path === 'clone remove') values.clone = String(planDevice(path, values, devices[0])[0].args.clone);
        const id = randomUUID();
        this.sessions.set(id, { kind: 'confirm', owner: i.user.id, expires: this.now() + 60_000, path, values,
          targets: devices.map(d => d.key) });
        return await i.editReply({ content: `Yakin mau ${routes[path].confirmText || (path === 'clone remove' ? 'hapus clone dari daftar (app tetap terpasang)' : 'hapus script dari Scripts (copy Autoexecute tetap ada)')}?\nTarget: ${devices.map(d => escape(d.name)).join(', ')}`, components: [new ActionRowBuilder().addComponents(button(`confirm:${id}`, routes[path].confirmLabel || 'Hapus', ButtonStyle.Danger), button(`cancel:${id}`, 'Batal'))], allowedMentions: mentions });
      }
      await this.queue(i, path, values, devices);
    } catch (e) {
      if (i.isAutocomplete()) {
        // Only the error kind and route go to the log, never option values.
        this.log(`autocomplete_failed ${interactionPath(i)} ${e?.code || e?.name || 'error'}`);
        try { await i.respond([]); } catch {}
        return;
      }
      const content = `❌ ${escape(e.message || 'Ada kesalahan; coba lagi.').slice(0, 1700)}`;
      try {
        if (i.deferred || i.replied) await i.editReply({ content, components: [], allowedMentions: mentions });
        else await i.reply({ content, flags: MessageFlags.Ephemeral, allowedMentions: mentions });
      } catch { this.log('discord_interaction_failed'); }
    }
  }

  async openCookieModal(i, values, view) {
    const device = selectDevices(view, 'cookie inject', values.device)[0];
    if (!this.store.online(device)) throw new Error('Device sedang offline; cookie tidak dikirim.');
    const clone = planDevice('cookie inject', values, device)[0].args.clone;
    const id = randomUUID();
    this.sessions.set(id, { kind: 'cookie', owner: i.user.id, expires: this.now() + 60_000, device: device.key, clone });
    const modal = new ModalBuilder().setCustomId(`cookie:${id}`).setTitle('Inject cookie Roblox');
    const input = new TextInputBuilder().setCustomId('token').setLabel('Cookie .ROBLOSECURITY')
      .setStyle(TextInputStyle.Short).setRequired(true).setMinLength(1).setMaxLength(2048)
      .setPlaceholder('Tempel cookie Roblox yang kamu miliki');
    modal.addComponents(new ActionRowBuilder().addComponents(input));
    await i.showModal(modal);
  }

  async cookieModal(i) {
    const [kind, id] = i.customId.split(':');
    const session = kind === 'cookie' ? this.sessions.get(id) : null;
    if (!session || session.kind !== 'cookie' || session.owner !== i.user.id || session.expires <= this.now()) {
      return await i.reply({ content: '⌛ Input cookie kedaluwarsa. Jalankan /cookie inject lagi.', flags: MessageFlags.Ephemeral });
    }
    this.sessions.delete(id);
    const token = i.fields.getTextInputValue('token').trim();
    if (!token || token.length > 2048 || /[\s'"\u0000-\u001f]/.test(token)) throw new Error('Format cookie tidak valid.');
    const device = this.store.devices.get(session.device);
    if (!device || !this.store.online(device)) throw new Error('Device sedang offline; cookie tidak dikirim.');
    if (!device.snapshot.instances.some(instance => instance.id === session.clone)) throw new Error('Clone berubah atau sudah dihapus; jalankan /cookie inject lagi.');
    await i.deferReply({ flags: MessageFlags.Ephemeral });
    const command = this.store.enqueue(device.key, 'cookie_inject', { clone: session.clone, token }, { sensitive: true });
    const group = this.replies.create(i, [{ command, interval: Number(setting(device, 'remote.interval')?.value) || 30, offline: false }]);
    await group.chain;
  }

  // CSV of logout alarms: preview (with a checked copy of the CSV) first, apply on the button.
  async previewAlarmImport(i, values, view) {
    const csv = await downloadAlarmCsv(values.file, this.fetcher);
    const rows = resolveAlarmRows(parseAlarmCsv(csv), view.devices, this.now());
    const ready = rows.filter(row => row.status === 'ready');
    const skipped = rows.filter(row => row.status === 'skipped').length;
    const invalid = rows.filter(row => row.status === 'invalid').length;
    const replacements = ready.filter(row => row.previousAlarm).length;
    const id = randomUUID();
    if (ready.length) {
      this.sessions.set(id, { kind: 'alarm_import', owner: i.user.id, expires: this.now() + 60_000,
        account: this.accounts.get(i.user.id), rows: ready });
    }
    const summary = [
      '📅 **Preview import alarm logout**',
      `Siap diterapkan: **${ready.length}** · baris bermasalah: **${invalid}** · Delete dicentang/dilewati: **${skipped}**`,
      replacements ? `⚠️ ${replacements} alarm lama akan diganti setelah konfirmasi.` : '',
      ready.length ? 'Cek file preview (device, USN, tanggal, jam) sebelum menekan Terapkan.' : 'Tidak ada baris valid untuk diterapkan.',
      invalid ? 'Baris bermasalah tidak dijadwalkan; perbaiki lalu upload ulang.' : '',
    ].filter(Boolean).join('\n');
    const components = ready.length ? [new ActionRowBuilder().addComponents(
      button(`alarmapply:${id}`, `${replacements ? 'Ganti & terapkan' : 'Terapkan'} ${ready.length} alarm`, ButtonStyle.Danger),
      button(`alarmcancel:${id}`, 'Batal'))] : [];
    await i.editReply({ content: summary, files: [{ attachment: alarmImportReport(rows), name: 'alarm-import-preview.csv' }], components, allowedMentions: mentions });
  }

  // Re-checks every row against the latest snapshot before queueing logout_alarm_set.
  async applyAlarmImport(i, session) {
    const account = this.accounts.get(i.user.id);
    const items = [];
    for (const row of session.rows) {
      const device = this.store.devices.get(row.deviceKey);
      const instance = device?.snapshot.instances.find(item => String(item.id) === String(row.cloneId));
      const label = `baris ${row.rowNumber} · ${row.deviceName}/${row.cloneName}`;
      let error = '';
      if (!device || device.account !== account || device.account !== session.account) error = 'Device berubah atau tidak lagi tersedia.';
      else if (!instance || String(instance.username || '').trim().toLocaleLowerCase() !== row.username.toLocaleLowerCase()) error = 'USN/clone berubah sejak preview.';
      else if (JSON.stringify(instance.logoutAlarm || null) !== JSON.stringify(row.previousAlarm || null)) error = 'Alarm clone berubah sejak preview; upload ulang.';
      if (error) { items.push({ device: label, error }); continue; }
      try {
        const command = this.store.enqueue(device.key, 'logout_alarm_set', { clone: row.cloneId, date: row.date, time: row.time, daily: row.daily === true });
        items.push({ command, interval: Number(setting(device, 'remote.interval')?.value) || 30, offline: !this.store.online(device), label });
      } catch (e) { items.push({ device: label, error: e.message || 'Gagal masuk antrean.' }); }
    }
    if (!items.some(item => item.command)) {
      return await i.editReply({ content: `Tidak ada alarm yang dikirim.\n${items.map(item => `❌ ${escape(item.device)}: ${escape(item.error)}`).join('\n')}`.slice(0, 1800), components: [], allowedMentions: mentions });
    }
    const group = this.replies.create(i, items);
    await group.chain;
  }

  // A Delta key the user got themselves: private modal, transient command (like cookies).
  async openDeltaKeyModal(i, values, view) {
    const device = selectDevices(view, 'delta input-key', values.device)[0];
    if (!this.store.online(device)) throw new Error('Device sedang offline; key tidak dikirim.');
    const id = randomUUID();
    this.sessions.set(id, { kind: 'delta_key', owner: i.user.id, expires: this.now() + 60_000, device: device.key });
    const modal = new ModalBuilder().setCustomId(`delta:${id}`).setTitle('Input Key Delta');
    const input = new TextInputBuilder().setCustomId('key').setLabel('Key Delta yang kamu dapat')
      .setStyle(TextInputStyle.Short).setRequired(true).setMinLength(1).setMaxLength(256)
      .setPlaceholder('FREE_XXXXX');
    modal.addComponents(new ActionRowBuilder().addComponents(input));
    await i.showModal(modal);
  }

  async deltaKeyModal(i) {
    const id = i.customId.split(':')[1];
    const session = this.sessions.get(id);
    if (!session || session.kind !== 'delta_key' || session.owner !== i.user.id || session.expires <= this.now()) {
      return await i.reply({ content: '⌛ Input key Delta kedaluwarsa. Jalankan /delta input-key lagi.', flags: MessageFlags.Ephemeral });
    }
    this.sessions.delete(id);
    const key = i.fields.getTextInputValue('key').trim();
    if (!key || key.length > 256 || /[\s\u0000-\u001f]/.test(key)) throw new Error('Format key Delta tidak valid.');
    const device = this.store.devices.get(session.device);
    if (!device || !this.store.online(device)) throw new Error('Device sedang offline; key tidak dikirim.');
    await i.deferReply({ flags: MessageFlags.Ephemeral });
    const command = this.store.enqueue(device.key, 'delta_key_input', { key }, { sensitive: true });
    const group = this.replies.create(i, [{ command, interval: Number(setting(device, 'remote.interval')?.value) || 30, offline: false }]);
    await group.chain;
  }

  // Register / unregister a device HWID for the caller; the device then syncs with it alone.
  async hwid(i, path, hwid) {
    if (!this.registry) throw new Error('Pendaftaran HWID belum aktif di bot ini.');
    if (path === 'hwid remove') {
      await this.registry.remove(hwid, i.user.id);
      return await i.editReply({ content: `🗑️ HWID \`${hwid}\` dihapus dari list kamu. Device itu ga bisa nyambung lagi.`, allowedMentions: mentions });
    }
    const added = await this.registry.add(hwid, i.user.id);
    await i.editReply({ content: `${added ? '✅ HWID didaftarkan' : 'ℹ️ HWID ini sudah terdaftar'} ke kamu: \`${hwid}\`.\nDevice-nya muncul di /devices dalam ±1 menit (monitor harus jalan). Ga perlu input apa-apa lagi di Termux.${this.registry.persistent ? '' : '\n⚠️ DATA_DIR (volume) / HWID_CHANNEL_ID belum diisi di bot: daftar HWID hilang tiap bot redeploy.'}`, allowedMentions: mentions });
  }

  async queue(i, path, values, devices) {
    const items = [];
    for (const device of devices) {
      try {
        const plans = planDevice(path, values, device);
        for (const p of plans) this.store.assertRename(device.key, renameTarget(p.type, p.args));
        for (const p of plans) {
          const command = this.store.enqueue(device.key, p.type, p.args);
          items.push({ command, interval: Number(setting(device, 'remote.interval')?.value) || 30,
            offline: !this.store.online(device), secret: Boolean(setting(device, p.args.key)?.secret) });
        }
      } catch (e) { items.push({ device: device.name, error: e.message }); }
    }
    // Register the reply group before yielding: a fast device may ACK during the first Discord edit.
    const group = this.replies.create(i, items);
    if (path === 'status') group.onComplete = async () => {
      if (items[0]?.result?.ok) await this.showStatus(i, this.store.devices.get(items[0].command.device));
    };
    await group.chain;
  }

  // Bot-side only: forget an offline device (and its pending commands). Nothing is sent to it.
  async removeDevice(i, device) {
    if (this.store.online(device)) throw new Error('Device ini online lagi; tidak dihapus.');
    this.store.removeDevice(device.key);
    await i.editReply({ content: `🗑️ Device ${escape(device.name)} dihapus dari daftar bot.`, components: [], allowedMentions: mentions });
  }

  async show(i, pages, refreshDevice = null) {
    const id = randomUUID();
    const session = { kind: 'pages', owner: i.user.id, expires: this.now() + 14 * 60_000, pages, page: 0, refreshDevice };
    this.sessions.set(id, session);
    await i.editReply(this.pagePayload(id, session));
  }

  pagePayload(id, session) {
    const controls = [];
    if (session.pages.length > 1) controls.push(button(`prev:${id}`, '◀', ButtonStyle.Secondary, session.page === 0), button(`next:${id}`, '▶', ButtonStyle.Secondary, session.page === session.pages.length - 1));
    if (session.refreshDevice) controls.push(button(`refresh:${id}`, '🔄 Refresh', ButtonStyle.Primary));
    return { content: '', embeds: [], ...session.pages[session.page], allowedMentions: mentions,
      components: controls.length ? [new ActionRowBuilder().addComponents(...controls)] : [] };
  }

  async showStatus(i, device) { await this.show(i, statusPages(this.store, device), device.key); }

  async component(i) {
    const [action, id] = i.customId.split(':');
    const session = this.sessions.get(id);
    if (!session || session.owner !== i.user.id || session.expires <= this.now()) {
      return await i.reply({ content: '⌛ Tombol kedaluwarsa atau bukan milikmu. Jalankan command lagi.', flags: MessageFlags.Ephemeral });
    }
    if (session.kind === 'alarm_import') {
      if (!['alarmapply', 'alarmcancel'].includes(action)) throw new Error('Tombol import alarm tidak valid.');
      this.sessions.delete(id);
      await i.deferUpdate();
      if (action === 'alarmcancel') return await i.editReply({ content: 'Import alarm dibatalkan; tidak ada jadwal yang diubah.', components: [], allowedMentions: mentions });
      return await this.applyAlarmImport(i, session);
    }
    if (session.kind === 'confirm') {
      if (!['confirm', 'cancel'].includes(action)) throw new Error('Tombol tidak valid.');
      this.sessions.delete(id);
      await i.deferUpdate();
      if (action === 'cancel') return await i.editReply({ content: 'Dibatalkan.', components: [], allowedMentions: mentions });
      const devices = session.targets.map(name => {
        const d = this.store.devices.get(name);
        if (!d) throw new Error('Target berubah nama atau tidak dikenal; jalankan command lagi.');
        return d;
      });
      if (session.path === 'device remove') return await this.removeDevice(i, devices[0]);
      await this.queue(i, session.path, session.values, devices);
      return;
    }
    if (!['refresh', 'prev', 'next'].includes(action)) throw new Error('Tombol tidak valid.');
    if (action === 'refresh') {
      const d = this.store.devices.get(session.refreshDevice);
      if (!d) throw new Error('Device berubah nama; jalankan /status lagi.');
      // Refresh gets its own ephemeral reply, preserving the paginated snapshot message.
      await i.deferReply({ flags: MessageFlags.Ephemeral });
      return await this.queue(i, 'status', {}, [d]);
    }
    session.page = Math.max(0, Math.min(session.pages.length - 1, session.page + (action === 'next' ? 1 : -1)));
    await i.update(this.pagePayload(id, session));
  }

  tick() { for (const [id, session] of this.sessions) if (session.expires <= this.now()) this.sessions.delete(id); }
}
