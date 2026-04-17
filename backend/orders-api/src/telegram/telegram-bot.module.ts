import { Module } from '@nestjs/common';
import { ClaudeClientService } from './claude-client.service';
import { TelegramApiService } from './telegram-api.service';
import { TelegramBotController } from './telegram-bot.controller';
import { TelegramBotService } from './telegram-bot.service';
import { TelegramSchemaService } from './telegram-schema.service';
import { TelegramSqlService } from './telegram-sql.service';

/**
 * Telegram ↔ Claude bot module.
 *
 * Depends on the global InfrastructureModule for `DbRouterService`; no extra
 * imports needed because InfrastructureModule is marked `@Global()`.
 */
@Module({
  controllers: [TelegramBotController],
  providers: [
    ClaudeClientService,
    TelegramApiService,
    TelegramSqlService,
    TelegramSchemaService,
    TelegramBotService,
  ],
  exports: [TelegramBotService],
})
export class TelegramBotModule {}
