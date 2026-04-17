import * as admin from 'firebase-admin';
import { Logger } from '@nestjs/common';

let app: admin.app.App | null = null;
const logger = new Logger('FirebaseAdmin');

export function getFirebaseApp(): admin.app.App {
  if (app) return app;
  const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) {
    throw new Error('Firebase Admin init failed: FIREBASE_PROJECT_ID/GOOGLE_CLOUD_PROJECT is missing');
  }
  try {
    if (admin.apps.length === 0) {
      app = admin.initializeApp({
        projectId,
      });
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
