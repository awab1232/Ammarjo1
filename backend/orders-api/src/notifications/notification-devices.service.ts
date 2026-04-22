import { Injectable, Logger } from '@nestjs/common';
import { OrdersPgService } from '../orders/orders-pg.service';

@Injectable()
export class NotificationDevicesService {
  private readonly logger = new Logger(NotificationDevicesService.name);

  constructor(private readonly pg: OrdersPgService) {}

  async registerDeviceToken(params: {
    userId: string;
    token: string;
    platform?: string;
  }): Promise<void> {
    const userId = params.userId.trim();
    const token = params.token.trim();
    const platform = (params.platform ?? 'unknown').trim().toLowerCase() || 'unknown';
    if (!userId || !token) return;

    await this.pg.withWriteClient(async (c) => {
      await c.query(
        `INSERT INTO user_devices (user_id, fcm_token, platform, last_seen_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (fcm_token) DO UPDATE
           SET user_id = EXCLUDED.user_id,
               platform = EXCLUDED.platform,
               last_seen_at = NOW()`,
        [userId, token, platform],
      );
      return true;
    });
  }

  async listActiveTokensByUser(userId: string): Promise<string[]> {
    const uid = userId.trim();
    if (!uid) return [];
    const rows =
      (await this.pg.withWriteClient(async (c) => {
        const r = await c.query<{ fcm_token: string }>(
          `SELECT fcm_token
           FROM user_devices
           WHERE user_id = $1
           ORDER BY last_seen_at DESC
           LIMIT 20`,
          [uid],
        );
        return r.rows;
      })) ?? [];
    return rows
      .map((r) => String(r.fcm_token ?? '').trim())
      .filter((t) => t.length > 0);
  }

  async pruneInvalidToken(token: string): Promise<void> {
    const t = token.trim();
    if (!t) return;
    await this.pg.withWriteClient(async (c) => {
      await c.query(`DELETE FROM user_devices WHERE fcm_token = $1`, [t]);
      return true;
    });
    this.logger.warn(JSON.stringify({ kind: 'notification_invalid_token_pruned' }));
  }
}
