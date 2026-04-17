/// Backend-owned ratings service placeholder.
class FirestoreEntityRatings {
  FirestoreEntityRatings._();

  static Future<void> submitStoreRating({
    required String storeId,
    required String userId,
    required String userName,
    required int rating,
    String comment = '',
  }) async {}

  static Future<void> submitTechnicianRating({
    required String techId,
    required String userId,
    required String userName,
    required int rating,
  }) async {}
}
