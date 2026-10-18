import { Client, Events, GatewayIntentBits } from 'discord.js';
import { pathToFileURL } from 'node:url';
import { readEnv } from './env.js';
import { Store } from './store.js';
import { createApi } from './http.js';
import { Replies } from './replies.js';
import { Handler } from './commands/handler.js';
import { registerCommands } from './register.js';

export async function start(config = readEnv(), {
  log = message => console.log(message),
  createClient = () => new Client({ intents: [GatewayIntentBits.Guilds] }),
  register = registerCommands,
} = {}) {
  const store = new Store({ timeoutMs: config.timeoutMs, dataDir: config.dataDir, log });
  await store.load();
  const replies = new Replies({ store, log });
  const handler = new Handler({ store, replies, owners: config.owners, guildId: config.guildId, log });
  const client = createClient();
  const server = createApi({ store, secret: config.secret, render: config.render, log });
  client.on(Events.InteractionCreate, interaction => { void handler.handle(interaction); });
  client.once(Events.ClientReady, ready => log(`logged in as ${ready.user.tag}`));
  client.on(Events.Error, () => log('discord_gateway_error'));
  const timer = setInterval(() => { store.tick(); replies.tick(); handler.tick(); }, 1000);
  timer.unref();
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    clearInterval(timer);
    replies.close();
    await client.destroy();
    await new Promise(resolve => { server.close(resolve); server.closeIdleConnections(); });
    await store.close();
  };
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(config.port, '0.0.0.0', resolve);
    });
    log(`listening on :${config.port}`);
    // Route handlers are ready before any command can be delivered over the gateway.
    await register(config);
    await client.login(config.token);
  } catch {
    await close();
    throw new Error('Startup gagal. Cek env, registrasi command, koneksi Discord, dan PORT.');
  }
  return { server, store, client, close };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const app = await start();
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => {
      const deadline = setTimeout(() => process.exit(1), 10_000);
      deadline.unref();
      void app.close().then(() => process.exit(0));
    });
  } catch (e) { console.error(e.message); process.exitCode = 1; }
}
