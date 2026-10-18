import { REST, Routes } from 'discord.js';
import { commandDefinitions } from './commands/definitions.js';

export async function registerCommands(config) {
  const rest = new REST({ version: '10' }).setToken(config.token);
  await rest.put(Routes.applicationGuildCommands(config.appId, config.guildId), { body: commandDefinitions() });
}
