import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { loadTelegramBotConfig } from './telegram-bot.config';
import { TelegramBotService } from './telegram-bot.service';
import type { TelegramUpdate } from './telegram-bot.types';

/**
 * Public Telegram webhook endpoint.
 *
 *   Telegram → POST /telegram/webhook → (this controller) → Claude → reply
 *
 * Configure Telegram with:
 *   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
 *        -d "url=https://<your-domain>/telegram/webhook" \
 *        -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
 *
 * The optional `secret_token` is echoed back by Telegram as the
 * `X-Telegram-Bot-Api-Secret-Token` header — we verify it here so
 * random internet callers cannot hit the endpoint.
 */
@Controller('telegram')
@UseGuards(TenantContextGuard, ApiPolicyGuard)
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 600 } })
export class TelegramBotController {
  constructor(private readonly bot: TelegramBotService) {}

  @Get('health')
  @HttpCode(HttpStatus.OK)
  health(): { ok: true; configured: boolean } {
    const cfg = loadTelegramBotConfig();
    return {
      ok: true,
      configured: cfg.telegramBotToken.length > 0 && cfg.anthropicApiKey.length > 0,
    };
  }

  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  async webhook(
    @Headers('x-telegram-bot-api-secret-token') secretHeader: string | undefined,
    @Body() body: TelegramUpdate,
  ): Promise<{ ok: true }> {
    const cfg = loadTelegramBotConfig();
    if (cfg.webhookSecret) {
      if (!secretHeader || !safeEqual(secretHeader, cfg.webhookSecret)) {
        throw new UnauthorizedException('invalid_webhook_secret');
      }
    }

    // Respond 200 to Telegram fast; process the update without blocking the HTTP reply.
    // Telegram retries on non-2xx, so we never want to surface our internal errors here.
    void this.bot.handleUpdate(body).catch(() => undefined);
    return { ok: true };
  }
}

/** Length-safe constant-time string compare; falls back to a simple loop. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
