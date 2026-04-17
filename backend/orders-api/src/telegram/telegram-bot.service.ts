import { Injectable, Logger } from '@nestjs/common';
import { ClaudeClientService } from './claude-client.service';
import { TelegramApiService } from './telegram-api.service';
import { TelegramSqlService } from './telegram-sql.service';
import {
  isChatAllowed,
  loadTelegramBotConfig,
  type TelegramBotConfig,
} from './telegram-bot.config';
import type {
  BotReply,
  ClaudeContentBlock,
  ClaudeMessage,
  ClaudeMessagesResponse,
  ClaudeToolDefinition,
  TelegramUpdate,
} from './telegram-bot.types';

const READ_TOOL = 'run_read_query';
const WRITE_TOOL = 'propose_write_query';

/** Canonical confirmation / cancellation words, Arabic + English. */
const CONFIRM_WORDS = new Set([
  'نعم',
  'أكد',
  'اكد',
  'تأكيد',
  'تاكيد',
  'موافق',
  'ok',
  'okay',
  'yes',
  'y',
  'confirm',
  'do it',
]);
const CANCEL_WORDS = new Set([
  'لا',
  'الغاء',
  'إلغاء',
  'رفض',
  'no',
  'n',
  'cancel',
  'abort',
]);

interface PendingWrite {
  sql: string;
  verb: 'INSERT' | 'UPDATE' | 'DELETE';
  summary: string;
  createdAt: number;
}

/**
 * Orchestrates a single Telegram update:
 *   user message → allowlist gate → (confirmation? / Claude loop) → reply.
 *
 * For write intents we require an explicit, typed confirmation in a second
 * message, held in an in-memory `Map` with a TTL. Restarting the backend
 * clears any pending confirmations — that is intentional (fail-safe).
 */
@Injectable()
export class TelegramBotService {
  private readonly logger = new Logger(TelegramBotService.name);
  private readonly cfg: TelegramBotConfig = loadTelegramBotConfig();
  private readonly pending = new Map<number, PendingWrite>();

  constructor(
    private readonly claude: ClaudeClientService,
    private readonly telegram: TelegramApiService,
    private readonly sql: TelegramSqlService,
  ) {}

  async handleUpdate(update: TelegramUpdate): Promise<void> {
    const msg = update.message ?? update.edited_message ?? update.channel_post;
    if (!msg?.chat || typeof msg.chat.id !== 'number') {
      return;
    }
    const chatId = msg.chat.id;
    const userId = msg.from?.id ?? null;
    const text = (msg.text ?? '').trim();
    if (!text) return;

    // 1) Admin allowlist — refuse early, and *log* the attempt with minimal data.
    if (!isChatAllowed(this.cfg, chatId)) {
      this.audit('denied_unauthorised_chat', { chatId, userId, textPreview: preview(text) });
      await this.telegram.sendMessage(
        chatId,
        'غير مصرح لك باستخدام هذا البوت. | Unauthorised.',
        msg.message_id,
      );
      return;
    }

    // 2) Built-in commands (no Claude call needed).
    if (text === '/start' || text === '/help') {
      await this.telegram.sendMessage(chatId, this.buildHelpText(chatId), msg.message_id);
      return;
    }
    if (text === '/cancel') {
      const had = this.pending.delete(chatId);
      await this.telegram.sendMessage(
        chatId,
        had ? 'تم إلغاء العملية المعلّقة.' : 'لا توجد عملية معلّقة للإلغاء.',
        msg.message_id,
      );
      return;
    }

    // 3) If there is a pending write, check for confirm / cancel BEFORE anything else.
    const pending = this.getLivePending(chatId);
    if (pending) {
      const normalized = text.toLowerCase();
      if (CONFIRM_WORDS.has(normalized)) {
        this.pending.delete(chatId);
        await this.executeConfirmedWrite(chatId, userId, pending, msg.message_id);
        return;
      }
      if (CANCEL_WORDS.has(normalized)) {
        this.pending.delete(chatId);
        this.audit('write_cancelled', { chatId, userId, verb: pending.verb });
        await this.telegram.sendMessage(chatId, 'تم إلغاء العملية. ❌', msg.message_id);
        return;
      }
      // Anything else while a write is pending: remind them — don't silently proceed.
      await this.telegram.sendMessage(
        chatId,
        [
          '⏳ لديك عملية معلّقة بانتظار التأكيد:',
          `▪️ ${pending.summary}`,
          '',
          'اكتب "نعم" للتأكيد أو "لا" للإلغاء.',
        ].join('\n'),
        msg.message_id,
      );
      return;
    }

    // 4) Normal path: Claude orchestrates reads + proposes writes.
    if (!this.claude.isConfigured() || !this.telegram.isConfigured()) {
      await this.telegram.sendMessage(
        chatId,
        'البوت غير مُهيّأ بالكامل. يرجى ضبط TELEGRAM_BOT_TOKEN و ANTHROPIC_API_KEY.',
        msg.message_id,
      );
      return;
    }

    await this.telegram.sendChatAction(chatId, 'typing');

    let reply: BotReply;
    try {
      reply = await this.runClaudeLoop(chatId, userId, text);
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      this.logger.warn(`[TelegramBot] Claude loop failed: ${errMsg}`);
      this.audit('claude_loop_failed', { chatId, userId, error: errMsg });
      reply = { text: 'تعذّر توليد رد الآن. حاول مرة أخرى خلال لحظات.', error: 'internal' };
    }
    await this.telegram.sendMessage(chatId, reply.text || 'لم أفهم الأمر.', msg.message_id);
  }

  /* ------------------------------------------------------------------ */
  /* Claude loop                                                         */
  /* ------------------------------------------------------------------ */

  private async runClaudeLoop(
    chatId: number,
    userId: number | null,
    userText: string,
  ): Promise<BotReply> {
    const messages: ClaudeMessage[] = [{ role: 'user', content: userText }];
    const tools = this.buildTools(chatId);
    const system = this.buildSystemPrompt(chatId);

    for (let i = 0; i < this.cfg.maxToolIterations; i++) {
      const response: ClaudeMessagesResponse = await this.claude.createMessage({
        system,
        messages,
        tools,
        maxTokens: 1024,
        temperature: 0.2,
      });

      messages.push({ role: 'assistant', content: response.content });

      const toolUses = response.content.filter(isToolUseBlock);
      if (toolUses.length === 0 || response.stop_reason !== 'tool_use') {
        const finalText = extractText(response.content).trim();
        return { text: finalText || 'لم أفهم الأمر.' };
      }

      // Process tools in order; a write-proposal short-circuits the whole loop
      // because we need the *user* to confirm before executing.
      const toolResults: ClaudeContentBlock[] = [];
      let proposed: PendingWrite | null = null;

      for (const tu of toolUses) {
        if (tu.name === READ_TOOL) {
          const r = await this.runReadTool(chatId, userId, tu.input);
          toolResults.push({
            type: 'tool_result',
            tool_use_id: tu.id,
            content: r.content,
            ...(r.isError ? { is_error: true } : {}),
          });
        } else if (tu.name === WRITE_TOOL) {
          const r = this.prepareWriteTool(chatId, userId, tu.input);
          toolResults.push({
            type: 'tool_result',
            tool_use_id: tu.id,
            content: r.content,
            ...(r.isError ? { is_error: true } : {}),
          });
          if (r.proposed) proposed = r.proposed;
        } else {
          toolResults.push({
            type: 'tool_result',
            tool_use_id: tu.id,
            content: `unknown_tool:${tu.name}`,
            is_error: true,
          });
        }
      }

      if (proposed) {
        this.pending.set(chatId, proposed);
        this.audit('write_proposed', {
          chatId,
          userId,
          verb: proposed.verb,
          summary: preview(proposed.summary),
          sql: preview(proposed.sql, 500),
        });
        return { text: this.renderConfirmationPrompt(proposed) };
      }

      messages.push({ role: 'user', content: toolResults });
    }

    return {
      text: 'تجاوزت محادثة الأدوات الحد المسموح. أعد صياغة طلبك بشكل أبسط من فضلك.',
      error: 'tool_iter_exceeded',
    };
  }

  /* ------------------------------------------------------------------ */
  /* Tool handlers                                                       */
  /* ------------------------------------------------------------------ */

  private async runReadTool(
    chatId: number,
    userId: number | null,
    input: Record<string, unknown>,
  ): Promise<{ content: string; isError: boolean }> {
    if (!this.sql.isEnabled() || !this.sql.isChatAllowed(chatId)) {
      return { content: 'sql_disabled_or_forbidden', isError: true };
    }
    const sql = typeof input.sql === 'string' ? input.sql : '';
    if (!sql.trim()) return { content: 'missing_sql', isError: true };

    const result = await this.sql.runReadOnlyQuery(sql);
    this.audit(result.ok ? 'read_ok' : 'read_failed', {
      chatId,
      userId,
      sql: preview(sql, 500),
      rowCount: result.rowCount,
      error: result.error,
    });
    if (!result.ok) {
      return { content: JSON.stringify({ ok: false, error: result.error }), isError: true };
    }
    const payload = {
      ok: true,
      rowCount: result.rowCount,
      truncated: result.truncated,
      columns: result.columns,
      rows: result.rows,
    };
    const serialised = JSON.stringify(payload);
    return {
      content: serialised.length > 16_000 ? `${serialised.slice(0, 16_000)}…` : serialised,
      isError: false,
    };
  }

  /**
   * Validates a Claude write proposal and returns the tool-result payload. We
   * do NOT execute the query here — we stash it and ask the user to confirm.
   */
  private prepareWriteTool(
    chatId: number,
    userId: number | null,
    input: Record<string, unknown>,
  ): { content: string; isError: boolean; proposed?: PendingWrite } {
    if (!this.sql.isWriteEnabled()) {
      return { content: 'writes_disabled', isError: true };
    }
    if (!this.sql.isChatAllowed(chatId)) {
      return { content: 'sql_forbidden_for_this_chat', isError: true };
    }
    const sql = typeof input.sql === 'string' ? input.sql : '';
    const summaryRaw = typeof input.summary === 'string' ? input.summary : '';
    if (!sql.trim()) return { content: 'missing_sql', isError: true };
    const summary = summaryRaw.trim() || 'عملية تعديل على قاعدة البيانات';

    const v = this.sql.validateWriteSql(sql);
    if (!v.ok) {
      this.audit('write_rejected_validation', {
        chatId,
        userId,
        sql: preview(sql, 500),
        error: v.error,
      });
      return {
        content: JSON.stringify({ ok: false, error: v.error }),
        isError: true,
      };
    }
    const proposed: PendingWrite = {
      sql: v.sql,
      verb: v.verb,
      summary,
      createdAt: Date.now(),
    };
    // Tool result tells Claude "I've queued it; reply to the user with a confirmation prompt."
    // But we short-circuit the Claude loop ourselves in `runClaudeLoop`, so Claude's next turn
    // doesn't matter — the bot's own prompt is what the user sees.
    return {
      content: JSON.stringify({
        ok: true,
        status: 'awaiting_user_confirmation',
        verb: v.verb,
        summary,
      }),
      isError: false,
      proposed,
    };
  }

  private async executeConfirmedWrite(
    chatId: number,
    userId: number | null,
    pending: PendingWrite,
    replyTo: number,
  ): Promise<void> {
    const result = await this.sql.runWriteQuery(pending.sql);
    this.audit(result.ok ? 'write_executed' : 'write_failed', {
      chatId,
      userId,
      verb: pending.verb,
      rowCount: result.rowCount,
      error: result.error,
      summary: preview(pending.summary),
      sql: preview(pending.sql, 500),
    });
    if (result.ok) {
      const rows = result.rowCount ?? 0;
      await this.telegram.sendMessage(
        chatId,
        [
          'تم بنجاح ✅',
          `العملية: ${pending.summary}`,
          `النوع: ${pending.verb}`,
          `عدد الصفوف المتأثرة: ${rows}`,
        ].join('\n'),
        replyTo,
      );
    } else {
      await this.telegram.sendMessage(
        chatId,
        [
          'فشل تنفيذ العملية ❌',
          `السبب: ${result.error ?? 'unknown'}`,
          '',
          'لم يتم تعديل أي بيانات — تم التراجع (ROLLBACK).',
        ].join('\n'),
        replyTo,
      );
    }
  }

  /* ------------------------------------------------------------------ */
  /* Prompts / tool defs                                                 */
  /* ------------------------------------------------------------------ */

  private buildTools(chatId: number): ClaudeToolDefinition[] {
    const out: ClaudeToolDefinition[] = [];
    if (this.sql.isEnabled() && this.sql.isChatAllowed(chatId)) {
      out.push({
        name: READ_TOOL,
        description:
          'Execute a single read-only SQL query (SELECT or CTE) against the Ammarjo PostgreSQL database. ' +
          `Results are capped to ${this.cfg.maxSqlRows} rows. ` +
          'Never attempt INSERT/UPDATE/DELETE/DDL — they will be rejected.',
        input_schema: {
          type: 'object',
          properties: {
            sql: {
              type: 'string',
              description: 'A single SELECT or WITH…SELECT statement. No trailing extra statements.',
            },
          },
          required: ['sql'],
          additionalProperties: false,
        },
      });
    }
    if (this.sql.isWriteEnabled() && this.sql.isChatAllowed(chatId)) {
      out.push({
        name: WRITE_TOOL,
        description:
          'Propose a single INSERT / UPDATE / DELETE statement. The query is NOT executed immediately — ' +
          'the backend will present a confirmation prompt to the user and only run it after they type "نعم" / "yes". ' +
          'UPDATE and DELETE MUST include a WHERE clause or they will be rejected.',
        input_schema: {
          type: 'object',
          properties: {
            sql: {
              type: 'string',
              description: 'A single INSERT, UPDATE, or DELETE statement. Single statement only.',
            },
            summary: {
              type: 'string',
              description:
                'Short, human-readable description of the operation in the user\'s language (Arabic preferred when they wrote in Arabic).',
            },
          },
          required: ['sql', 'summary'],
          additionalProperties: false,
        },
      });
    }
    return out;
  }

  private buildSystemPrompt(chatId: number): string {
    const canWrite = this.sql.isWriteEnabled() && this.sql.isChatAllowed(chatId);
    const canRead = this.sql.isEnabled() && this.sql.isChatAllowed(chatId);
    const lines: string[] = [
      'You are the Ammarjo database agent, powered by Claude, responding inside a Telegram chat.',
      'Always answer in the same language the user used. Prefer Arabic if the user wrote Arabic.',
      'Keep replies concise and formatted for plain-text Telegram (no Markdown formatting, no code fences).',
      canRead
        ? `For data-lookup questions (e.g. "كم عدد المتاجر؟") call the ${READ_TOOL} tool with a SELECT. Then summarise the result for the user in natural language.`
        : 'Read-SQL tooling is disabled for this chat.',
      canWrite
        ? `For modification requests (e.g. "اخصم 200 من متجر أحمد", "احذف متجر X", "وافق على متجر Y") call the ${WRITE_TOOL} tool with a single INSERT/UPDATE/DELETE. The backend will show a confirmation prompt to the user; do NOT claim the change is already done.`
        : 'Write-SQL tooling is disabled for this chat — politely refuse modification requests.',
      'If the user\'s intent is unclear, ask a short clarifying question instead of guessing a query.',
      'If you cannot map the request to a safe SQL statement, reply with "لم أفهم الأمر" (or English equivalent).',
      'NEVER invent table or column names. If you are unsure which schema exists, run a SELECT against information_schema first (for example, information_schema.tables) before proposing a write.',
    ];
    return lines.join(' ');
  }

  private renderConfirmationPrompt(p: PendingWrite): string {
    return [
      '⚠️ هل أنت متأكد؟ اكتب "نعم" للتأكيد',
      '',
      `العملية: ${p.summary}`,
      `النوع: ${p.verb}`,
      '',
      'SQL المقترح:',
      truncate(p.sql, 600),
      '',
      `ستنتهي صلاحية التأكيد خلال ${Math.round(this.cfg.pendingTtlMs / 1000)} ثانية.`,
      'اكتب "لا" أو /cancel للإلغاء.',
    ].join('\n');
  }

  private buildHelpText(chatId: number): string {
    const canWrite = this.sql.isWriteEnabled() && this.sql.isChatAllowed(chatId);
    return [
      'مرحباً! أنا وكيل Ammarjo المدعوم بـ Claude لإدارة قاعدة البيانات.',
      '',
      'أمثلة:',
      '• "كم عدد المتاجر؟"',
      '• "أظهر آخر 5 طلبات"',
      ...(canWrite
        ? [
            '• "اخصم 200 من عمولات متجر أحمد"',
            '• "وافق على متجر رقم 42"',
            '• "احذف المنتج X"',
          ]
        : []),
      '',
      canWrite
        ? 'قبل أي تعديل سأعرض عليك تأكيداً — اكتب "نعم" للتنفيذ أو "لا" للإلغاء.'
        : 'هذا الحساب يملك صلاحية القراءة فقط.',
      '',
      'الأوامر: /start • /help • /cancel',
    ].join('\n');
  }

  /* ------------------------------------------------------------------ */
  /* Helpers                                                             */
  /* ------------------------------------------------------------------ */

  private getLivePending(chatId: number): PendingWrite | null {
    const p = this.pending.get(chatId);
    if (!p) return null;
    if (Date.now() - p.createdAt > this.cfg.pendingTtlMs) {
      this.pending.delete(chatId);
      return null;
    }
    return p;
  }

  /**
   * Structured audit log for every bot action. Keep keys short and stable so
   * downstream log aggregators (Railway → Datadog / Grafana) can filter by
   * `kind` without schema surprises. Sensitive SQL is truncated.
   */
  private audit(kind: string, data: Record<string, unknown>): void {
    try {
      this.logger.log(
        JSON.stringify({
          ts: new Date().toISOString(),
          component: 'telegram-bot',
          kind,
          ...data,
        }),
      );
    } catch {
      /* logging must never throw */
    }
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

function preview(s: string, n = 120): string {
  const oneLine = s.replace(/\s+/g, ' ').trim();
  return oneLine.length > n ? `${oneLine.slice(0, n)}…` : oneLine;
}

function truncate(s: string, n: number): string {
  return s.length > n ? `${s.slice(0, n)}…` : s;
}
