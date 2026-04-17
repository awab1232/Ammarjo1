/**
 * Minimal typings for the pieces of the Telegram Bot API and Anthropic Messages API
 * that this module actually touches. Kept intentionally narrow — we never trust the
 * raw payload, so every field is optional and validated at runtime.
 */

export interface TelegramChat {
  id: number;
  type?: string;
  username?: string;
  first_name?: string;
  title?: string;
}

export interface TelegramUser {
  id: number;
  is_bot?: boolean;
  username?: string;
  first_name?: string;
  language_code?: string;
}

export interface TelegramMessage {
  message_id: number;
  date?: number;
  chat: TelegramChat;
  from?: TelegramUser;
  text?: string;
}

export interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
  edited_message?: TelegramMessage;
  channel_post?: TelegramMessage;
}

/* ---------- Anthropic Messages API (subset) ---------- */

export interface ClaudeTextBlock {
  type: 'text';
  text: string;
}

export interface ClaudeToolUseBlock {
  type: 'tool_use';
  id: string;
  name: string;
  input: Record<string, unknown>;
}

export interface ClaudeToolResultBlock {
  type: 'tool_result';
  tool_use_id: string;
  content: string;
  is_error?: boolean;
}

export type ClaudeContentBlock = ClaudeTextBlock | ClaudeToolUseBlock | ClaudeToolResultBlock;

export interface ClaudeMessage {
  role: 'user' | 'assistant';
  content: string | ClaudeContentBlock[];
}

export interface ClaudeToolDefinition {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

export interface ClaudeMessagesRequest {
  model: string;
  max_tokens: number;
  system?: string;
  messages: ClaudeMessage[];
  tools?: ClaudeToolDefinition[];
  temperature?: number;
}

export interface ClaudeMessagesResponse {
  id: string;
  type: 'message';
  role: 'assistant';
  content: ClaudeContentBlock[];
  stop_reason: 'end_turn' | 'tool_use' | 'max_tokens' | 'stop_sequence' | string;
  model: string;
  usage?: { input_tokens: number; output_tokens: number };
}

/* ---------- Internal orchestrator result ---------- */

export interface BotReply {
  text: string;
  error?: string;
}
