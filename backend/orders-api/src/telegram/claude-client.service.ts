import { Injectable, Logger } from '@nestjs/common';
import { loadTelegramBotConfig, type TelegramBotConfig } from './telegram-bot.config';
import type {
  ClaudeMessage,
  ClaudeMessagesRequest,
  ClaudeMessagesResponse,
  ClaudeToolDefinition,
} from './telegram-bot.types';

/**
 * Thin wrapper over Anthropic's Messages API. We intentionally keep this tiny
 * (no SDK dependency) so the Railway image stays slim and upgrade paths are easy.
 */
@Injectable()
export class ClaudeClientService {
  private readonly logger = new Logger(ClaudeClientService.name);
  private readonly cfg: TelegramBotConfig = loadTelegramBotConfig();

  isConfigured(): boolean {
    return this.cfg.anthropicApiKey.length > 0;
  }

  async createMessage(params: {
    system: string;
    messages: ClaudeMessage[];
    tools?: ClaudeToolDefinition[];
    maxTokens?: number;
    temperature?: number;
  }): Promise<ClaudeMessagesResponse> {
    if (!this.isConfigured()) {
      throw new Error('anthropic_api_key_missing');
    }
    const body: ClaudeMessagesRequest = {
      model: this.cfg.claudeModel,
      max_tokens: params.maxTokens ?? 1024,
      system: params.system,
      messages: params.messages,
      ...(params.tools && params.tools.length > 0 ? { tools: params.tools } : {}),
      ...(typeof params.temperature === 'number' ? { temperature: params.temperature } : {}),
    };

    const res = await fetch(`${this.cfg.anthropicBaseUrl}/v1/messages`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': this.cfg.anthropicApiKey,
        'anthropic-version': this.cfg.anthropicVersion,
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const errText = await safeReadText(res);
      this.logger.warn(`[Claude] HTTP ${res.status}: ${truncate(errText, 400)}`);
      throw new Error(`claude_http_${res.status}`);
    }
    const json = (await res.json()) as ClaudeMessagesResponse;
    return json;
  }
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
