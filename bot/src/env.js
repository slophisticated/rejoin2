export function readEnv(env = process.env) {
  const required = ['DISCORD_TOKEN', 'APP_ID', 'GUILD_ID', 'OWNER_IDS', 'DEVICE_SECRET'];
  for (const key of required) {
    if (!env[key]?.trim()) throw new Error(`Env ${key} wajib diisi.`);
  }
  for (const key of ['APP_ID', 'GUILD_ID']) {
    if (!/^\d{17,20}$/.test(env[key])) throw new Error(`Env ${key} harus ID Discord.`);
  }
  const owners = new Set(env.OWNER_IDS.split(',').map(s => s.trim()).filter(Boolean));
  if (!owners.size || ![...owners].every(s => /^\d{17,20}$/.test(s))) throw new Error('OWNER_IDS harus berisi ID Discord.');
  if (env.DEVICE_SECRET.length < 32) throw new Error('DEVICE_SECRET minimal 32 karakter.');
  const port = Number(env.PORT || 3000);
  const timeout = Number(env.COMMAND_TIMEOUT_SEC || 90);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT tidak valid.');
  if (!Number.isFinite(timeout) || timeout < 1) throw new Error('COMMAND_TIMEOUT_SEC tidak valid.');
  return {
    token: env.DISCORD_TOKEN, appId: env.APP_ID, guildId: env.GUILD_ID,
    owners, secret: env.DEVICE_SECRET, port, timeoutMs: timeout * 1000,
    dataDir: env.DATA_DIR?.trim() || null, render: env.RENDER === 'true',
  };
}
