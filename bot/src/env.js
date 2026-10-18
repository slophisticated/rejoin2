import { createHash } from 'node:crypto';

const discordId = s => /^\d{17,20}$/.test(s);
// Stable account key from the secret, so persisted devices survive env reordering.
export const accountOf = secret => createHash('sha256').update(secret).digest('hex').slice(0, 16);

// Accounts: OWNERS="ownerId:secret,ownerId:secret" (one secret per owner = their own devices).
// The legacy pair OWNER_IDS + DEVICE_SECRET is one shared account (''); DEVICE_SECRET is
// optional since devices can be registered by HWID (/hwid redeem). HWID_USERS get an
// account of their own (`u<id>`).
function readAccounts(env) {
  const accounts = new Map();
  const secrets = [];
  const mapIds = (ids, account, key) => {
    for (const id of ids) {
      if (!discordId(id)) throw new Error(`${key} harus berisi ID Discord.`);
      if (accounts.has(id) && accounts.get(id) !== account) throw new Error(`${key}: ID ${id} terdaftar di dua secret.`);
      accounts.set(id, account);
    }
  };
  const add = (ids, secret, account, key) => {
    if (secret.length < 32) throw new Error(`${key}: secret minimal 32 karakter.`);
    if (!secrets.some(s => s.secret === secret)) secrets.push({ account, secret });
    mapIds(ids, account, key);
  };
  const list = v => (v || '').split(',').map(s => s.trim()).filter(Boolean);
  const owners = env.OWNERS?.trim();
  if (owners) {
    for (const entry of owners.split(',').map(s => s.trim()).filter(Boolean)) {
      const at = entry.indexOf(':');
      if (at < 1) throw new Error('OWNERS formatnya ownerId:secret, dipisah koma.');
      const secret = entry.slice(at + 1).trim();
      add([entry.slice(0, at).trim()], secret, accountOf(secret), 'OWNERS');
    }
  }
  const hwidUsers = list(env.HWID_USERS);
  if (env.OWNER_IDS?.trim() || env.DEVICE_SECRET?.trim() || (!owners && !hwidUsers.length)) {
    if (!env.OWNER_IDS?.trim()) throw new Error('Env OWNER_IDS wajib diisi (atau pakai OWNERS / HWID_USERS).');
    const ids = list(env.OWNER_IDS);
    if (!ids.length) throw new Error('OWNER_IDS harus berisi ID Discord.');
    if (env.DEVICE_SECRET?.trim()) {
      if (env.DEVICE_SECRET.length < 32) throw new Error('DEVICE_SECRET minimal 32 karakter.');
      add(ids, env.DEVICE_SECRET, '', 'OWNER_IDS');
    } else mapIds(ids, '', 'OWNER_IDS');
  }
  // HWID-only users: their own account unless a secret already gave them one.
  for (const id of hwidUsers) if (!accounts.has(id)) mapIds([id], `u${id}`, 'HWID_USERS');
  return { accounts, secrets };
}

export function readEnv(env = process.env) {
  for (const key of ['DISCORD_TOKEN', 'APP_ID', 'GUILD_ID']) {
    if (!env[key]?.trim()) throw new Error(`Env ${key} wajib diisi.`);
  }
  for (const key of ['APP_ID', 'GUILD_ID']) {
    if (!discordId(env[key])) throw new Error(`Env ${key} harus ID Discord.`);
  }
  const { accounts, secrets } = readAccounts(env);
  const hwidChannelId = env.HWID_CHANNEL_ID?.trim() || null;
  if (hwidChannelId && !discordId(hwidChannelId)) throw new Error('HWID_CHANNEL_ID harus ID channel Discord.');
  const port = Number(env.PORT || 3000);
  const timeout = Number(env.COMMAND_TIMEOUT_SEC || 90);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT tidak valid.');
  if (!Number.isFinite(timeout) || timeout < 1) throw new Error('COMMAND_TIMEOUT_SEC tidak valid.');
  return {
    token: env.DISCORD_TOKEN, appId: env.APP_ID, guildId: env.GUILD_ID,
    owners: new Set(accounts.keys()), accounts, secrets, port,
    hwidChannelId, timeoutMs: timeout * 1000,
    dataDir: env.DATA_DIR?.trim() || null, render: env.RENDER === 'true',
  };
}
