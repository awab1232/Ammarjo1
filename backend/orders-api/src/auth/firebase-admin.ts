import * as admin from 'firebase-admin';

let app: admin.app.App | undefined;

export function initFirebase(): admin.app.App {
  if (app) {
    return app;
  }

  const base64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;

  if (!base64) {
    console.error('❌ FIREBASE_SERVICE_ACCOUNT_BASE64 missing');
    throw new Error('Firebase config missing');
  }

  const json = Buffer.from(base64, 'base64').toString('utf8');
  const serviceAccount = JSON.parse(json) as Record<string, unknown>;

  console.log('🔥 Firebase Admin Initializing...');
  console.log('🔥 Firebase project:', serviceAccount.project_id);

  if (admin.apps.length > 0) {
    app = admin.app();
    return app;
  }

  app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
  });

  return app;
}

export function getFirebaseApp(): admin.app.App {
  return initFirebase();
}

export function getFirebaseAuth(): admin.auth.Auth {
  return initFirebase().auth();
}
