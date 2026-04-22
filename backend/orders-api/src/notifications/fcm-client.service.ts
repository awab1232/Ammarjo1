import { Injectable, Logger } from '@nestjs/common';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import type { NotificationPayload } from './notifications.types';

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
  private readonly app: App | null;
  private readonly notificationsEnabled: boolean;

  constructor() {
    this.notificationsEnabled = (process.env.NOTIFICATIONS_ENABLED ?? 'false').trim().toLowerCase() === 'true';
    this.app = this.initApp();
  }

  private initApp(): App | null {
    if (!this.notificationsEnabled) {
      this.logger.log('Notifications disabled');
      return null;
    }
    const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
    const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
    if (!projectId || !clientEmail || !privateKey) {
      throw new Error(
        'NOTIFICATIONS_ENABLED=true but FIREBASE_PROJECT_ID/FIREBASE_CLIENT_EMAIL/FIREBASE_PRIVATE_KEY are missing',
      );
    }
    const existing = getApps().find((a) => a.name === 'orders-api-fcm');
    if (existing) return existing;
    try {
      return initializeApp(
        {
          credential: cert({
            projectId,
            clientEmail,
            privateKey,
          }),
          projectId,
        },
        'orders-api-fcm',
      );
    } catch (e) {
      this.logger.warn(`FCM disabled: initialization failed (${e instanceof Error ? e.message : String(e)})`);
      return null;
    }
  }

  private isReady(): boolean {
    return this.app != null;
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
    try {
      await getMessaging(this.app!).send({
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
    try {
      const out = await getMessaging(this.app!).sendEachForMulticast({
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

