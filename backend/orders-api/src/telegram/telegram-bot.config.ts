/**
 * Env-driven configuration for the Telegram ↔ Claude agent.
 *
 * Security: every secret (Telegram bot token, Anthropic API key, webhook
 * secret) MUST come from process.env. Never hard-code credentials in source.
 *
 * This config also gates full bot access:
 *   - `allowedChatIds` is the admin allowlist for the **entire** bot. When
 *     non-empty, only those chats receive any reply at all (even for /start).
 *   - `sqlAllowedChatIds` narrows SQL tooling further, if you want the bot
 *     to be chat-open but keep database tooling locked to a subset.
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
  /** Admin allowlist — only these chat_ids may talk to the bot at all. */
  allowedChatIds: Set<number>;
  /** Narrower list: chats that may trigger SQL tooling. Defaults to allowedChatIds. */
  sqlAllowedChatIds: Set<number>;
  /** Whether SQL is enabled at all. */
  sqlEnabled: boolean;
  /** Whether INSERT / UPDATE / DELETE are allowed (after confirmation). */
  writeEnabled: boolean;
  /** TTL for a pending-write confirmation in milliseconds. */
  pendingTtlMs: number;
}

function parseChatIds(raw: string | undefined): Set<number> {
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

  // Accept either the singular or plural name so operators can paste a single
  // id or a comma-separated list into the same variable.
  const allowed = parseChatIds(
    process.env.TELEGRAM_ALLOWED_CHAT_ID || process.env.TELEGRAM_ALLOWED_CHAT_IDS,
  );
  const sqlAllowed = parseChatIds(process.env.TELEGRAM_SQL_ALLOWED_CHAT_IDS);

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
    allowedChatIds: allowed,
    // Default SQL scope mirrors the top-level allowlist so "admin-only" is the
    // sensible default; set TELEGRAM_SQL_ALLOWED_CHAT_IDS explicitly to narrow further.
    sqlAllowedChatIds: sqlAllowed.size > 0 ? sqlAllowed : allowed,
    sqlEnabled: (process.env.TELEGRAM_BOT_SQL_ENABLED?.trim() || 'true').toLowerCase() !== 'false',
    writeEnabled:
      (process.env.TELEGRAM_BOT_WRITE_ENABLED?.trim() || 'true').toLowerCase() !== 'false',
    pendingTtlMs: Math.max(5_000, Number(process.env.TELEGRAM_BOT_PENDING_TTL_MS || 120_000)),
  };
}

export function isTelegramBotConfigured(cfg: TelegramBotConfig): boolean {
  return cfg.telegramBotToken.length > 0 && cfg.anthropicApiKey.length > 0;
}

/**
 * Returns true when the bot is unrestricted (no allowlist) OR the chat is
 * explicitly allow-listed. When the allowlist is empty the bot is effectively
 * public — callers should typically refuse this in production.
 */
export function isChatAllowed(cfg: TelegramBotConfig, chatId: number): boolean {
  if (cfg.allowedChatIds.size === 0) return true;
  return cfg.allowedChatIds.has(chatId);
}
