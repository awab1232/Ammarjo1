import { Injectable, Logger } from '@nestjs/common';
import { loadTelegramBotConfig, type TelegramBotConfig } from './telegram-bot.config';

/**
 * Minimal Telegram Bot API client — only the calls we actually use.
 * Docs: https://core.telegram.org/bots/api
 */
@Injectable()
export class TelegramApiService {
  private readonly logger = new Logger(TelegramApiService.name);
  private readonly cfg: TelegramBotConfig = loadTelegramBotConfig();

  isConfigured(): boolean {
    return this.cfg.telegramBotToken.length > 0;
  }

  /** Send a text reply. Long messages are chunked to Telegram's 4096-char limit. */
  async sendMessage(chatId: number, text: string, replyTo?: number): Promise<void> {
    if (!this.isConfigured()) {
      this.logger.warn('[TelegramApi] sendMessage skipped: bot token missing');
      return;
    }
    const chunks = chunkText(text || '...', 4000);
    for (let i = 0; i < chunks.length; i++) {
      const body: Record<string, unknown> = {
        chat_id: chatId,
        text: chunks[i],
        disable_web_page_preview: true,
      };
      if (i === 0 && typeof replyTo === 'number') {
        body.reply_to_message_id = replyTo;
      }
      try {
        const res = await fetch(
          `https://api.telegram.org/bot${encodeURIComponent(this.cfg.telegramBotToken)}/sendMessage`,
          {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(body),
          },
        );
        if (!res.ok) {
          const errText = await safeReadText(res);
          this.logger.warn(`[TelegramApi] sendMessage HTTP ${res.status}: ${truncate(errText, 300)}`);
          return;
        }
      } catch (e) {
        this.logger.warn(`[TelegramApi] sendMessage error: ${e instanceof Error ? e.message : String(e)}`);
        return;
      }
    }
  }

  /** Indicate "typing…" in the chat while we wait for Claude. */
  async sendChatAction(chatId: number, action: 'typing' = 'typing'): Promise<void> {
    if (!this.isConfigured()) return;
    try {
      await fetch(
        `https://api.telegram.org/bot${encodeURIComponent(this.cfg.telegramBotToken)}/sendChatAction`,
        {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ chat_id: chatId, action }),
        },
      );
    } catch {
      /* best-effort; never block the reply flow on a typing indicator */
    }
  }
}

function chunkText(text: string, max: number): string[] {
  if (text.length <= max) return [text];
  const out: string[] = [];
  let i = 0;
  while (i < text.length) {
    out.push(text.slice(i, i + max));
    i += max;
  }
  return out;
}

async function safeReadText(res: Response): Promise<string> {
  try {
    return await res.text();
  } catch {
    return '';
  }
}

function truncate(s: string, n: number): string {
  return s.length > n ? `${s.slice(0, n)}…` : s;
}
