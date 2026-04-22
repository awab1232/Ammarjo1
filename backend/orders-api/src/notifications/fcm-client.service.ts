import { Injectable, Logger } from '@nestjs/common';
import { getMessaging } from 'firebase-admin/messaging';
import type { NotificationPayload } from './notifications.types';
import { getFirebaseApp } from '../auth/firebase-admin';

export type FcmDispatchResult = {
  success: boolean;
  successCount: number;
  failureCount: number;
  invalidTokens: string[];
  errorMessage?: string;
};

@Injectable()
export class FcmClientService {
  private readonly logger = new Logger(FcmClientService.name);
  private appInitialized = false;
  private readonly notificationsEnabled: boolean;

  constructor() {
    this.notificationsEnabled = (process.env.NOTIFICATIONS_ENABLED ?? 'false').trim().toLowerCase() === 'true';
    if (!this.notificationsEnabled) this.logger.log('Notifications disabled');
  }

  private isReady(): boolean {
    return this.notificationsEnabled;
  }

  private getAppOrNull() {
    if (!this.notificationsEnabled) return null;
    if (this.appInitialized) {
      try {
        return getFirebaseApp();
      } catch {
        return null;
      }
    }
    this.appInitialized = true;
    try {
      return getFirebaseApp();
    } catch (e) {
      const reason = e instanceof Error ? e.message : String(e);
      this.logger.warn(`FCM unavailable: ${reason}`);
      return null;
    }
  }

  async sendToUser(userId: string, token: string, payload: NotificationPayload): Promise<FcmDispatchResult> {
    if (!this.isReady()) {
      return {
        success: false,
        successCount: 0,
        failureCount: 1,
        invalidTokens: [],
        errorMessage: 'fcm_not_ready',
      };
    }
    const app = this.getAppOrNull();
    if (!app) {
      return {
        success: false,
        successCount: 0,
        failureCount: 1,
        invalidTokens: [],
        errorMessage: 'fcm_not_ready',
      };
    }
    try {
      await getMessaging(app).send({
        token,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
      });
      return { success: true, successCount: 1, failureCount: 0, invalidTokens: [] };
    } catch (e) {
      const reason = e instanceof Error ? e.message : String(e);
      this.logger.warn(
        JSON.stringify({
          kind: 'fcm_send_to_user_failed',
          userId,
          reason,
        }),
      );
      return {
        success: false,
        successCount: 0,
        failureCount: 1,
        invalidTokens: isInvalidTokenError(reason) ? [token] : [],
        errorMessage: reason,
      };
    }
  }

  async sendToMultiple(
    userIds: string[],
    tokens: string[],
    payload: NotificationPayload,
  ): Promise<FcmDispatchResult> {
    if (!this.isReady() || tokens.length === 0) {
      return {
        success: false,
        successCount: 0,
        failureCount: tokens.length,
        invalidTokens: [],
        errorMessage: !this.isReady() ? 'fcm_not_ready' : 'no_tokens',
      };
    }
    const app = this.getAppOrNull();
    if (!app) {
      return {
        success: false,
        successCount: 0,
        failureCount: tokens.length,
        invalidTokens: [],
        errorMessage: 'fcm_not_ready',
      };
    }
    try {
      const out = await getMessaging(app).sendEachForMulticast({
        tokens,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
      });
      const invalidTokens: string[] = [];
      out.responses.forEach((resp, idx) => {
        if (resp.success) return;
        const msg = resp.error?.message ?? '';
        if (isInvalidTokenError(msg)) {
          const token = tokens[idx];
          if (token) invalidTokens.push(token);
        }
      });
      return {
        success: out.successCount > 0 && out.failureCount == 0,
        successCount: out.successCount,
        failureCount: out.failureCount,
        invalidTokens,
        errorMessage: out.failureCount > 0 ? 'partial_failure' : undefined,
      };
    } catch (e) {
      const reason = e instanceof Error ? e.message : String(e);
      this.logger.warn(
        JSON.stringify({
          kind: 'fcm_send_to_multiple_failed',
          userIds,
          reason,
        }),
      );
      return {
        success: false,
        successCount: 0,
        failureCount: tokens.length,
        invalidTokens: [],
        errorMessage: reason,
      };
    }
  }
}

function isInvalidTokenError(message: string): boolean {
  const v = message.toLowerCase();
  return (
    v.includes('registration-token-not-registered') ||
    v.includes('invalid registration token') ||
    v.includes('invalid-argument')
  );
}

