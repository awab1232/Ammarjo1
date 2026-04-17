/// Import anchor for production hardening: this library must **not** import
/// `cloud_firestore` or Firebase Firestore APIs. It exists so `main.dart` and
/// backend bootstrap keep a visible policy hook without pulling Firestore.
///
/// See [FirestoreGuard] for the explicit runtime failure mode if a forbidden
/// code path is invoked.
library;

import 'firestore_guard.dart';

/// Called from application entry so the policy module stays on the import graph.
void ensureFirestorePolicyHookLoaded() {}
