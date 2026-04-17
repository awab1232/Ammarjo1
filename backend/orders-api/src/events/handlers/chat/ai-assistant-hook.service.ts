import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class AiAssistantHookService {
  private readonly logger = new Logger(AiAssistantHookService.name);

  onConversationCreated(payload: Record<string, unknown>): void {
    setImmediate(() => {
      this.logger.log(
        JSON.stringify({
          kind: 'ai_assistant_conversation_created_hook',
          payload,
        }),
      );
    });
  }
}

