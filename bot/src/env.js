import { createHash } from 'node:crypto';

const discordId = s => /^\d{17,20}$/.test(s);
// Stable account key from the secret, so persisted devices survive env reordering.
export const accountOf = secret => createHash('sha256').update(secret).digest('hex').slice(0, 16);

// Accounts: OWNERS="ownerId:secret,ownerId:secret" (one secret per owner = their own devices).
// The legacy pair OWNER_IDS + DEVICE_SECRET is one shared account ('').
function readAccounts(env) {
  const accounts = new Map();
  const secrets = [];
  const add = (ids, secret, account, key) => {
    if (secret.length < 32) throw new Error(`${key}: secret minimal 32 karakter.`);
    if (!secrets.some(s => s.secret === secret)) secrets.push({ account, secret });
    for (const id of ids) {
      if (!discordId(id)) throw new Error(`${key} harus berisi ID Discord.`);
      if (accounts.has(id) && accounts.get(id) !== account) throw new Error(`${key}: ID ${id} terdaftar di dua secret.`);
      accounts.set(id, account);
    }
  };
  const owners = env.OWNERS?.trim();
  if (owners) {
    for (const entry of owners.split(',').map(s => s.trim()).filter(Boolean)) {
      const at = entry.indexOf(':');
      if (at < 1) throw new Error('OWNERS formatnya ownerId:secret, dipisah koma.');
      const secret = entry.slice(at + 1).trim();
      add([entry.slice(0, at).trim()], secret, accountOf(secret), 'OWNERS');
    }
  }
  if (!owners || env.OWNER_IDS?.trim() || env.DEVICE_SECRET?.trim()) {
    for (const key of ['OWNER_IDS', 'DEVICE_SECRET']) {
      if (!env[key]?.trim()) throw new Error(`Env ${key} wajib diisi (atau pakai OWNERS).`);
    }
    const ids = env.OWNER_IDS.split(',').map(s => s.trim()).filter(Boolean);
    if (!ids.length) throw new Error('OWNER_IDS harus berisi ID Discord.');
    if (env.DEVICE_SECRET.length < 32) throw new Error('DEVICE_SECRET minimal 32 karakter.');
    add(ids, env.DEVICE_SECRET, '', 'OWNER_IDS');
  }
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
  const port = Number(env.PORT || 3000);
  const timeout = Number(env.COMMAND_TIMEOUT_SEC || 90);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT tidak valid.');
  if (!Number.isFinite(timeout) || timeout < 1) throw new Error('COMMAND_TIMEOUT_SEC tidak valid.');
  return {
    token: env.DISCORD_TOKEN, appId: env.APP_ID, guildId: env.GUILD_ID,
    owners: new Set(accounts.keys()), accounts, secrets, port, timeoutMs: timeout * 1000,
    dataDir: env.DATA_DIR?.trim() || null, render: env.RENDER === 'true',
  };
}
