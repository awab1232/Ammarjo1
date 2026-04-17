export type ChatConversationType =
  | 'store_customer'
  | 'home_store_customer'
  | 'technician_customer'
  | 'support';

export type ChatMessageSentPayload = {
  conversationId?: unknown;
  senderId?: unknown;
  type?: unknown;
  [k: string]: unknown;
};

export type ChatMessageReadPayload = {
  conversationId?: unknown;
  readerId?: unknown;
  [k: string]: unknown;
};

export type ChatConversationPayload = {
  conversationId?: unknown;
  type?: unknown;
  participants?: unknown;
  [k: string]: unknown;
};

export function toConversationType(value: unknown): ChatConversationType | 'unknown' {
  const v = typeof value === 'string' ? value.trim() : '';
  if (
    v === 'store_customer' ||
    v === 'home_store_customer' ||
    v === 'technician_customer' ||
    v === 'support'
  ) {
    return v;
  }
  return 'unknown';
}

export function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  return v.length > 0 ? v : null;
}

export function toParticipants(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((x) => (typeof x === 'string' ? x.trim() : ''))
    .filter((x) => x.length > 0);
}

