import * as admin from 'firebase-admin';
import { Logger } from '@nestjs/common';

let app: admin.app.App | null = null;
const logger = new Logger('FirebaseAdmin');

export function getFirebaseApp(): admin.app.App {
  if (app) return app;
  const base64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64?.trim();
  if (!base64) {
    throw new Error('Firebase Admin init failed: Missing FIREBASE_SERVICE_ACCOUNT_BASE64');
  }
  let serviceAccount: Record<string, unknown>;
  try {
    serviceAccount = JSON.parse(Buffer.from(base64, 'base64').toString('utf8'));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Firebase Admin init failed: invalid FIREBASE_SERVICE_ACCOUNT_BASE64 (${message})`);
  }
  try {
    if (admin.apps.length === 0) {
      app = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      console.log('Firebase project:', serviceAccount.project_id);
      console.log('[FIREBASE] Initialized with project:', serviceAccount.project_id);
      console.log('[FIREBASE] Project ID:', serviceAccount.project_id);
    } else {
      app = admin.app();
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logger.warn(`Firebase Admin init failed: ${message}`);
    throw new Error(`Firebase Admin init failed: ${message}`);
  }
  return app;
}

export function getFirebaseAuth(): admin.auth.Auth {
  return getFirebaseApp().auth();
}
