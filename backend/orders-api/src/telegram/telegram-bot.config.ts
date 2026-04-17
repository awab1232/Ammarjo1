/**
 * Env-driven configuration for the Telegram ↔ Claude bot.
 *
 * Security: every secret (Telegram bot token, Anthropic API key, webhook secret)
 * MUST come from process.env. Never hard-code credentials in source.
 */

export interface TelegramBotConfig {
  telegramBotToken: string;
  anthropicApiKey: string;
  /** Optional shared-secret header Telegram will send back on every webhook call. */
  webhookSecret: string | null;
  /** Claude model id — default is a stable, production-grade Sonnet. */
  claudeModel: string;
  /** Anthropic Messages API base URL (override for proxies if needed). */
  anthropicBaseUrl: string;
  /** Anthropic API version header. */
  anthropicVersion: string;
  /** Max iterations of tool-use loop (prevents infinite tool chains). */
  maxToolIterations: number;
  /** Hard cap on rows returned from SQL so we never flood Telegram. */
  maxSqlRows: number;
  /** Per-statement SQL timeout in milliseconds. */
  sqlStatementTimeoutMs: number;
  /** If set, only these chat_ids may invoke SQL tools (comma-separated). */
  sqlAllowedChatIds: Set<number>;
  /** Whether SQL is enabled at all. */
  sqlEnabled: boolean;
}

function parseAllowedChatIds(raw: string | undefined): Set<number> {
  if (!raw) return new Set();
  const out = new Set<number>();
  for (const piece of raw.split(',')) {
    const n = Number(piece.trim());
    if (Number.isFinite(n) && n !== 0) {
      out.add(n);
    }
  }
  return out;
}

export function loadTelegramBotConfig(): TelegramBotConfig {
  const telegramBotToken = process.env.TELEGRAM_BOT_TOKEN?.trim() ?? '';
  const anthropicApiKey = process.env.ANTHROPIC_API_KEY?.trim() ?? '';
  return {
    telegramBotToken,
    anthropicApiKey,
    webhookSecret: process.env.TELEGRAM_WEBHOOK_SECRET?.trim() || null,
    claudeModel: process.env.CLAUDE_MODEL?.trim() || 'claude-sonnet-4-5-20250929',
    anthropicBaseUrl: process.env.ANTHROPIC_BASE_URL?.trim() || 'https://api.anthropic.com',
    anthropicVersion: process.env.ANTHROPIC_VERSION?.trim() || '2023-06-01',
    maxToolIterations: Math.max(1, Number(process.env.TELEGRAM_BOT_MAX_TOOL_ITER || 4)),
    maxSqlRows: Math.max(1, Number(process.env.TELEGRAM_BOT_MAX_SQL_ROWS || 50)),
    sqlStatementTimeoutMs: Math.max(500, Number(process.env.TELEGRAM_BOT_SQL_TIMEOUT_MS || 5000)),
    sqlAllowedChatIds: parseAllowedChatIds(process.env.TELEGRAM_SQL_ALLOWED_CHAT_IDS),
    sqlEnabled: (process.env.TELEGRAM_BOT_SQL_ENABLED?.trim() || 'true').toLowerCase() !== 'false',
  };
}

export function isTelegramBotConfigured(cfg: TelegramBotConfig): boolean {
  return cfg.telegramBotToken.length > 0 && cfg.anthropicApiKey.length > 0;
}
