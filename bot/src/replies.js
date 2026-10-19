import { MessageFlags } from 'discord.js';
import { chunks, mentions, resultLine, safeName } from './format.js';

export class Replies {
  constructor({ store, now = Date.now, log = () => {} }) {
    this.store = store;
    this.now = now;
    this.log = log;
    this.groups = new Set();
    this.byCommand = new Map();
    this.onResult = (c, result) => {
      const entry = this.byCommand.get(c.id);
      if (!entry) { this.log('ack_received_no_active_interaction'); return; }
      entry.item.result = { ...result, data: c.type === 'script_get' ? result.data : undefined };
      entry.item.fileReadyAt = this.now();
      entry.group.revision++;
      this.byCommand.delete(c.id);
      void this.update(entry.group);
    };
    this.onTimeout = c => {
      const entry = this.byCommand.get(c.id);
      if (entry) { entry.group.revision++; void this.update(entry.group); }
    };
    store.on('result', this.onResult);
    store.on('timeout', this.onTimeout);
  }

  create(interaction, items) {
    const group = { interaction, items, revision: 0, createdAt: interaction.createdTimestamp ?? this.now(), chain: Promise.resolve(), messages: [], originalHasFile: false, expired: false };
    this.groups.add(group);
    for (const item of items) if (item.command) this.byCommand.set(item.command.id, { group, item });
    void this.update(group);
    return group;
  }

  expire(group) {
    group.expired = true;
    this.groups.delete(group);
    for (const item of group.items) {
      if (item.command) this.byCommand.delete(item.command.id);
      if (item.result) { delete item.result.buffer; delete item.result.data; }
    }
  }

  async render(group) {
    if (group.expired || this.now() - group.createdAt >= 14 * 60_000 + 50_000) { this.expire(group); return; }
    const revision = group.revision;
    const interaction = group.interaction;
    const limit = Math.min(interaction.attachmentSizeLimit || 8 * 1024 * 1024, 8 * 1024 * 1024);
    const pending = [];
    for (const item of group.items) {
      if (!item.result?.ok || item.fileSent) continue;
      let attachment, name;
      if (item.command.type === 'screenshot' && item.result.buffer) {
        attachment = item.result.buffer;
        name = `screenshot-${safeName(item.command.name || item.command.device)}.png`;
      } else if (item.command.type === 'script_get' && typeof item.result.data?.content === 'string') {
        attachment = Buffer.from(item.result.data.content);
        name = safeName(item.result.data.name || item.command.args.name);
      }
      if (!attachment) continue;
      if (attachment.length > limit) {
        item.result = { ok: false, message: 'File melewati batas attachment Discord untuk interaction ini.' };
        continue;
      }
      pending.push({ item, file: { attachment, name } });
    }
    const pages = chunks(group.items.map(resultLine));
    let first = [];
    if (!group.originalHasFile && pending.length) {
      let bytes = 0;
      while (pending.length && first.length < 10 && bytes + pending[0].file.attachment.length <= limit) {
        const next = pending.shift();
        first.push(next); bytes += next.file.attachment.length;
      }
    }
    await interaction.editReply({ content: pages[0], components: [], embeds: [], allowedMentions: mentions, ...(first.length ? { files: first.map(x => x.file) } : {}) });
    if (first.length) group.originalHasFile = true;
    for (const entry of first) this.releaseFile(entry.item);
    for (let i = 1; i < pages.length; i++) {
      const payload = { content: pages[i], allowedMentions: mentions };
      if (group.messages[i]) await interaction.webhook.editMessage(group.messages[i], payload);
      else group.messages[i] = (await interaction.followUp({ ...payload, flags: MessageFlags.Ephemeral })).id;
    }
    for (let i = pages.length; i < group.messages.length; i++) {
      if (group.messages[i]) { await interaction.webhook.deleteMessage(group.messages[i]); group.messages[i] = null; }
    }
    while (pending.length) {
      const batch = [];
      let bytes = 0;
      while (pending.length && batch.length < 10 && bytes + pending[0].file.attachment.length <= limit) {
        const next = pending.shift(); batch.push(next); bytes += next.file.attachment.length;
      }
      await interaction.followUp({ content: '📎 File dari device:', files: batch.map(x => x.file), flags: MessageFlags.Ephemeral, allowedMentions: mentions });
      for (const entry of batch) this.releaseFile(entry.item);
    }
    if (revision === group.revision && group.items.every(item => item.error || item.result) && group.items.every(item => !item.result?.buffer && !item.result?.data)) {
      if (group.onComplete) await group.onComplete();
      this.expire(group);
    }
  }

  releaseFile(item) {
    item.fileSent = true;
    delete item.result.buffer;
    delete item.result.data;
  }

  update(group) {
    group.chain = group.chain.then(async () => {
      await this.render(group);
      group.nextRetry = null;
      group.retryDelay = 2000;
    }).catch(() => {
      this.log('discord_reply_failed');
      group.retryDelay = Math.min((group.retryDelay || 1000) * 2, 30_000);
      group.nextRetry = this.now() + group.retryDelay;
    });
    return group.chain;
  }

  tick() {
    for (const group of this.groups) {
      if (this.now() - group.createdAt >= 14 * 60_000 + 50_000) this.expire(group);
      else {
        if (group.nextRetry && this.now() >= group.nextRetry) {
          group.nextRetry = null;
          void this.update(group);
        }
        for (const item of group.items) {
          if (item.result?.buffer && this.now() - (item.fileReadyAt ??= this.now()) >= 300_000) {
            item.result = { ok: false, message: 'Screenshot kedaluwarsa sebelum berhasil dikirim ke Discord.' };
            group.revision++;
            void this.update(group);
          }
        }
      }
    }
  }

  close() {
    this.store.off('result', this.onResult);
    this.store.off('timeout', this.onTimeout);
    for (const group of this.groups) this.expire(group);
  }
}
