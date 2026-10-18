import { SlashCommandBuilder } from 'discord.js';

// Each route defines the public interface once for registration, dispatch and autocomplete.
const s = (name, required = false, autocomplete = false) => ({ name, kind: 'String', required, autocomplete });
const b = name => ({ name, kind: 'Boolean' });
const n = name => ({ name, kind: 'Integer' });
const device = s('device', false, true);
const preset = s('preset', true, true);
const clone = s('clone', true, true);
const name = s('name', true);
const key = s('key', true, true);
const script = s('name', true, true);
const rejoin = b('rejoin');
// Options autocompleted from a device's snapshot (preset, clone, script, setting key) need
// the device picked first; Discord lists required options first, so device leads there.
const route = (description, options = [], extra = {}) => ({ description,
  options: options.some(o => o.autocomplete) ? [{ ...device, required: true }, ...options] : [...options, device], ...extra });

export const routes = {
  status: route('Lihat status clone dari snapshot terakhir.'),
  devices: { description: 'Lihat semua device yang dikenal.', options: [] },
  game: route('Pindah game semua clone atau clone pilihan.', [preset, s('clones', false, true), rejoin], { all: true }),
  default: route('Ganti default; preset khusus tetap dipakai.', [preset, rejoin], { all: true }),
  'preset list': route('Lihat preset game.'),
  'preset set': route('Tambah atau ubah preset game.', [s('key', true), name, s('link', true), rejoin], { all: true }),
  'preset remove': route('Hapus preset selain default.', [key], { all: true }),
  'clone list': route('Lihat daftar clone.'),
  'clone add': route('Tambah clone ke daftar device.', [name, s('package', true), s('preset', false, true), s('link')]),
  'clone edit': route('Ubah clone; preset default berarti ikut default.', [clone, s('name'), s('package'), s('preset', false, true), s('link')]),
  'clone remove': route('Hapus clone dari daftar dengan konfirmasi.', [clone], { confirm: true }),
  restart: route('Rejoin clone pilihan, atau all untuk Launch All.', [s('clones', true, true)]),
  screenshot: route('Ambil screenshot layar device saat ini.', [], { all: true }),
  'config get': route('Lihat nilai setting dari schema device.', [s('key', false, true)]),
  'config set': route('Ubah satu setting yang diizinkan device.', [key, s('value', true)], { all: true }),
  'webhook set': route('Atur URL webhook; tidak ditampilkan ulang.', [s('url', true)], { all: true }),
  'webhook options': route('Atur laporan status dan notifikasi key.', [n('interval'), b('screenshot'), b('notif_key'), b('hide_names')], { all: true }),
  'webhook test': route('Kirim laporan webhook sekarang.'),
  'device rename': route('Ganti nama device.', [name]),
  'device replace': route('Lanjutkan pesan status device lama.', [s('message_link', true)], { options: [s('message_link', true), { ...device, required: true }] }),
  window: route('Atur grid jendela floating.', [b('enabled'), n('columns'), n('gap'), n('overlap')], { all: true }),
  saver: route('Atur heartbeat dan mode hemat.', [b('heartbeat'), b('enabled'), n('fps_cap'), b('disable3d')], { all: true }),
  launch: route('Atur jeda Launch All.', [n('join_timeout'), n('settle'), n('empty')], { all: true }),
  'script list': route('Lihat Scripts dan copy di Autoexecute.'),
  'script add': route('Simpan script dari file, URL, atau code ke Scripts.', [name, { name: 'file', kind: 'Attachment' }, s('url'), s('code')], { all: true }),
  'script view': route('Unduh isi script sebagai file.', [script]),
  'script remove': route('Hapus dari Scripts dengan konfirmasi.', [script], { all: true, confirm: true }),
  'autoexec list': route('Lihat isi Autoexecute.'),
  'autoexec add': route('Copy script dari Scripts ke Autoexecute.', [script, rejoin], { all: true }),
  'autoexec remove': route('Hapus copy di Autoexecute; Scripts tetap.', [script, rejoin], { all: true }),
};

const descriptions = {
  device: 'Pilih device dulu (all = semua device kalau didukung).',
  preset: 'Kode preset game.', clones: 'Nama, ID, atau package; pisahkan dengan koma. all = semua.',
  clone: 'Nama, ID, atau package clone.', rejoin: 'Rejoin setelah perubahan?',
  key: 'Kode preset atau key setting.', value: 'Nilai baru; bool: true/false/on/off/ya/tidak/1/0.',
  name: 'Nama preset, clone, device, atau file script.', package: 'Package Android, mis. com.apengjers.v7.',
  link: 'Link Roblox; edit clone: - untuk hapus link sendiri.', url: 'URL HTTPS.',
  file: 'Attachment teks .lua atau .txt, maksimal 200 KB.', code: 'Isi script pendek; jangan diisi bersama file atau url.',
  message_link: 'Link pesan status Discord lama atau ID pesan.',
};

function addOptions(builder, options) {
  for (const option of [...options].sort((a, z) => Number(Boolean(z.required)) - Number(Boolean(a.required)))) {
    builder[`add${option.kind}Option`](input => {
      input.setName(option.name).setDescription(descriptions[option.name] || `Atur ${option.name}.`).setRequired(Boolean(option.required));
      if (option.autocomplete) input.setAutocomplete(true);
      if (option.kind === 'String') input.setMaxLength(option.name === 'code' || option.name === 'clones' ? 4000 : 300);
      return input;
    });
  }
  return builder;
}

export function commandDefinitions() {
  const builders = new Map();
  for (const [path, spec] of Object.entries(routes)) {
    const [root, sub] = path.split(' ');
    let builder = builders.get(root);
    if (!builder) {
      builder = new SlashCommandBuilder().setName(root).setDescription(sub ? `Kelola ${root} Rejoin.` : spec.description).setDMPermission(false);
      builders.set(root, builder);
    }
    if (sub) builder.addSubcommand(child => addOptions(child.setName(sub).setDescription(spec.description), spec.options));
    else addOptions(builder, spec.options);
  }
  return [...builders.values()].map(builder => builder.toJSON());
}

export function interactionPath(interaction) {
  const sub = interaction.options.getSubcommand(false);
  return `${interaction.commandName}${sub ? ` ${sub}` : ''}`;
}

export function interactionValues(interaction, path) {
  const values = {};
  for (const o of routes[path].options) {
    const value = interaction.options[`get${o.kind}`](o.name);
    if (value !== null && value !== undefined) values[o.name] = value;
  }
  return values;
}
