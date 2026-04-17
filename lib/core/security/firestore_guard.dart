/// Runtime guard for accidental Firestore usage outside the communication domain.
///
/// **Policy:** `cloud_firestore` / Firestore APIs must only appear under
/// `lib/features/communication/**`. Enforce with repo search in CI:
/// `rg "cloud_firestore|FirebaseFirestore" lib -g "*.dart"` → only communication paths.
class FirestoreGuard {
  static void assertNoFirestoreUsage() {
    throw StateError(
      'FIRESTORE DETECTED OUTSIDE COMMUNICATION DOMAIN - BLOCKED IN PRODUCTION',
    );
  }
}
