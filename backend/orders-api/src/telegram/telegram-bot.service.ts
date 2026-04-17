import { Injectable, Logger } from '@nestjs/common';
import { ClaudeClientService } from './claude-client.service';
import { TelegramApiService } from './telegram-api.service';
import { TelegramSqlService } from './telegram-sql.service';
import { loadTelegramBotConfig, type TelegramBotConfig } from './telegram-bot.config';
import type {
  BotReply,
  ClaudeContentBlock,
  ClaudeMessage,
  ClaudeMessagesResponse,
  ClaudeToolDefinition,
  TelegramUpdate,
} from './telegram-bot.types';

const SQL_TOOL_NAME = 'run_sql_query';

/**
 * Orchestrates a single Telegram update:
 *  user message → Claude → (optional) SQL tool loop → final reply back to Telegram.
 *
 * The function is non-throwing end-to-end: any internal failure is turned into
 * a polite error message for the user, so a misbehaving Claude/DB never causes
 * Telegram to retry the webhook forever.
 */
@Injectable()
export class TelegramBotService {
  private readonly logger = new Logger(TelegramBotService.name);
  private readonly cfg: TelegramBotConfig = loadTelegramBotConfig();

  constructor(
    private readonly claude: ClaudeClientService,
    private readonly telegram: TelegramApiService,
    private readonly sql: TelegramSqlService,
  ) {}

  async handleUpdate(update: TelegramUpdate): Promise<void> {
    const msg = update.message ?? update.edited_message ?? update.channel_post;
    if (!msg || !msg.chat || typeof msg.chat.id !== 'number') {
      return;
    }
    const chatId = msg.chat.id;
    const text = (msg.text ?? '').trim();
    if (!text) {
      return;
    }

    // Handle the canonical "/start" + "/help" commands without spending a Claude call.
    if (text === '/start' || text === '/help') {
      await this.telegram.sendMessage(
        chatId,
        [
          'مرحباً! أنا بوت Ammarjo مدعوم بـ Claude.',
          'اسألني أي شيء بالعربية أو الإنجليزية، ويمكنني أيضاً تشغيل استعلامات قراءة فقط على قاعدة البيانات بناءً على طلبك.',
          '',
          'Hi! I am the Ammarjo Claude-powered bot.',
          'Ask me anything. I can also run read-only SQL against the orders database when you ask.',
        ].join('\n'),
        msg.message_id,
      );
      return;
    }

    // Fail loudly-but-friendly if the operator hasn't configured secrets yet.
    if (!this.claude.isConfigured() || !this.telegram.isConfigured()) {
      await this.telegram.sendMessage(
        chatId,
        'البوت غير مُهيّأ بالكامل حالياً. يرجى تزويد TELEGRAM_BOT_TOKEN و ANTHROPIC_API_KEY في متغيرات البيئة.',
        msg.message_id,
      );
      return;
    }

    await this.telegram.sendChatAction(chatId, 'typing');

    let reply: BotReply;
    try {
      reply = await this.runClaudeLoop(chatId, text);
    } catch (e) {
      this.logger.warn(`[TelegramBot] runClaudeLoop failed: ${e instanceof Error ? e.message : String(e)}`);
      reply = { text: 'تعذّر توليد رد الآن. حاول مرة أخرى خلال لحظات.', error: 'internal' };
    }

    await this.telegram.sendMessage(chatId, reply.text || '...', msg.message_id);
  }

  /**
   * Drives the Claude `tool_use` loop. Claude may ask to run SQL via the
   * `run_sql_query` tool; we execute, feed the result back, and continue until
   * the model returns a normal `end_turn` (or we hit the iteration cap).
   */
  private async runClaudeLoop(chatId: number, userText: string): Promise<BotReply> {
    const messages: ClaudeMessage[] = [{ role: 'user', content: userText }];
    const tools = this.buildTools(chatId);
    const system = this.buildSystemPrompt(chatId);

    for (let i = 0; i < this.cfg.maxToolIterations; i++) {
      const response: ClaudeMessagesResponse = await this.claude.createMessage({
        system,
        messages,
        tools,
        maxTokens: 1024,
        temperature: 0.3,
      });

      // Append the assistant turn verbatim so Claude sees its own tool_use ids.
      messages.push({ role: 'assistant', content: response.content });

      const toolUses = response.content.filter(isToolUseBlock);
      if (toolUses.length === 0 || response.stop_reason !== 'tool_use') {
        const finalText = extractText(response.content).trim();
        return { text: finalText || 'تم.' };
      }

      const toolResults: ClaudeContentBlock[] = [];
      for (const tu of toolUses) {
        if (tu.name === SQL_TOOL_NAME) {
          const rendered = await this.runSqlTool(chatId, tu.input);
          toolResults.push({
            type: 'tool_result',
            tool_use_id: tu.id,
            content: rendered.content,
            ...(rendered.isError ? { is_error: true } : {}),
          });
        } else {
          toolResults.push({
            type: 'tool_result',
            tool_use_id: tu.id,
            content: `unknown_tool:${tu.name}`,
            is_error: true,
          });
        }
      }
      messages.push({ role: 'user', content: toolResults });
    }

    return {
      text: 'تجاوزت محادثة الأدوات الحد المسموح. أعد صياغة طلبك بشكل أبسط من فضلك.',
      error: 'tool_iter_exceeded',
    };
  }

  private async runSqlTool(
    chatId: number,
    input: Record<string, unknown>,
  ): Promise<{ content: string; isError: boolean }> {
    if (!this.sql.isEnabled()) {
      return { content: 'sql_disabled', isError: true };
    }
    if (!this.sql.isChatAllowed(chatId)) {
      return { content: 'sql_forbidden_for_this_chat', isError: true };
    }
    const sqlRaw = typeof input.sql === 'string' ? input.sql : '';
    if (!sqlRaw.trim()) {
      return { content: 'missing_sql', isError: true };
    }
    const result = await this.sql.runReadOnlyQuery(sqlRaw);
    if (!result.ok) {
      return { content: JSON.stringify({ ok: false, error: result.error }), isError: true };
    }
    // Keep the payload compact; JSON is enough for Claude to summarise.
    const payload = {
      ok: true,
      rowCount: result.rowCount,
      truncated: result.truncated,
      columns: result.columns,
      rows: result.rows,
    };
    const serialised = JSON.stringify(payload);
    // Defensive cap so one runaway tool call never bloats the Claude context.
    return { content: serialised.length > 16_000 ? `${serialised.slice(0, 16_000)}…` : serialised, isError: false };
  }

  private buildTools(chatId: number): ClaudeToolDefinition[] {
    if (!this.sql.isEnabled() || !this.sql.isChatAllowed(chatId)) {
      return [];
    }
    return [
      {
        name: SQL_TOOL_NAME,
        description:
          'Execute a single read-only SQL query (SELECT or CTE) against the Ammarjo PostgreSQL database. ' +
          'Use this ONLY when the user explicitly asks for data. ' +
          `Results are capped to ${this.cfg.maxSqlRows} rows. ` +
          'Never attempt INSERT/UPDATE/DELETE/DDL — they will be rejected.',
        input_schema: {
          type: 'object',
          properties: {
            sql: {
              type: 'string',
              description:
                'A single SELECT (or WITH … SELECT) statement. No semicolons terminating extra statements.',
            },
          },
          required: ['sql'],
          additionalProperties: false,
        },
      },
    ];
  }

  private buildSystemPrompt(chatId: number): string {
    const sqlAllowed = this.sql.isEnabled() && this.sql.isChatAllowed(chatId);
    return [
      'You are the Ammarjo assistant, powered by Claude, responding inside a Telegram chat.',
      'Always answer in the same language the user used. Prefer Arabic if the user wrote Arabic.',
      'Keep replies concise and formatted for plain-text Telegram (no Markdown formatting).',
      sqlAllowed
        ? `You have access to a read-only tool "${SQL_TOOL_NAME}" that runs a single SELECT against PostgreSQL. ` +
          'Use it only when the user explicitly asks for data that lives in the database. ' +
          'If you are unsure which tables exist, say so instead of guessing — do not hallucinate schema.'
        : 'SQL tooling is disabled for this chat; never claim to execute database queries.',
    ].join(' ');
  }
}

function isToolUseBlock(
  b: ClaudeContentBlock,
): b is Extract<ClaudeContentBlock, { type: 'tool_use' }> {
  return b.type === 'tool_use';
}

function extractText(blocks: ClaudeContentBlock[]): string {
  return blocks
    .filter((b): b is Extract<ClaudeContentBlock, { type: 'text' }> => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
}
