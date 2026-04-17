export const DomainEventNames = {
  ORDER_CREATED: 'order.created',
  ORDER_UPDATED: 'order.updated',
  PRODUCT_CREATED: 'product.created',
  PRODUCT_UPDATED: 'product.updated',
  STOCK_UPDATED: 'stock.updated',
  CHAT_MESSAGE_SENT: 'message.sent',
  CHAT_MESSAGE_READ: 'message.read',
  CHAT_CONVERSATION_CREATED: 'conversation.created',
  CHAT_CONVERSATION_UPDATED: 'conversation.updated',
  SERVICE_REQUEST_CREATED: 'service_request.created',
  SERVICE_REQUEST_ASSIGNED: 'service_request.assigned',
  SERVICE_REQUEST_STARTED: 'service_request.started',
  SERVICE_REQUEST_COMPLETED: 'service_request.completed',
  SERVICE_REQUEST_CANCELLED: 'service_request.cancelled',
  SERVICE_REQUEST_AUTO_ASSIGNED: 'service_request.auto_assigned',
  RATING_CREATED: 'rating.created',
  WHOLESALE_ORDER_CREATED: 'wholesale_order.created',
  WHOLESALE_PRODUCT_VIEWED: 'wholesale_product.viewed',
  WHOLESALE_PRICE_CHANGED: 'wholesale_price.changed',
  STORE_BUILDER_BOOTSTRAPPED: 'store_builder.bootstrapped',
  STORE_BUILDER_MODE_CHANGED: 'store_builder.mode_changed',
  STORE_BUILDER_CATEGORY_UPDATED: 'store_builder.category_updated',
  STORE_BUILDER_SUGGESTION_CREATED: 'store_builder.suggestion_created',
} as const;

export type DomainEventName = (typeof DomainEventNames)[keyof typeof DomainEventNames];

const DOMAIN_EVENT_NAME_SET = new Set<string>(Object.values(DomainEventNames));

export function isDomainEventName(value: string): value is DomainEventName {
  return DOMAIN_EVENT_NAME_SET.has(value);
}
