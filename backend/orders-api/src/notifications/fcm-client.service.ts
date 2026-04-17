import { Injectable, Logger } from '@nestjs/common';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import type { NotificationPayload } from './notifications.types';

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

  async sendToUser(userId: string, token: string, payload: NotificationPayload): Promise<void> {
    if (!this.isReady()) return;
    try {
      await getMessaging(this.app!).send({
        token,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
      });
    } catch (e) {
      this.logger.warn(
        JSON.stringify({
          kind: 'fcm_send_to_user_failed',
          userId,
          reason: e instanceof Error ? e.message : String(e),
        }),
      );
    }
  }

  async sendToMultiple(
    userIds: string[],
    tokens: string[],
    payload: NotificationPayload,
  ): Promise<void> {
    if (!this.isReady() || tokens.length === 0) return;
    try {
      await getMessaging(this.app!).sendEachForMulticast({
        tokens,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
      });
    } catch (e) {
      this.logger.warn(
        JSON.stringify({
          kind: 'fcm_send_to_multiple_failed',
          userIds,
          reason: e instanceof Error ? e.message : String(e),
        }),
      );
    }
  }
}

