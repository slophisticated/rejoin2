import { readEnv } from '../src/env.js';
import { registerCommands } from '../src/register.js';

try {
  await registerCommands(readEnv());
  console.log('Slash command guild sudah didaftarkan.');
} catch {
  console.error('Registrasi gagal. Cek env, ID aplikasi/guild, token, dan koneksi Discord.');
  process.exitCode = 1;
}
