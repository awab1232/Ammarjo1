export type NotificationPayload = {
  title: string;
  body: string;
  data?: Record<string, string>;
};

export type NewMessageNotificationInput = {
  conversationId: string;
  senderId?: string | null;
  targetUserId?: string | null;
};

export type ServiceAssignedNotificationInput = {
  requestId: string;
  technicianId: string;
};

export type ServiceCompletedNotificationInput = {
  requestId: string;
  customerId: string;
};

export type RatingReceivedNotificationInput = {
  targetId: string;
  targetType: string;
  targetUserId?: string | null;
};

