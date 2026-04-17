/// طلب فتح متجر (واجهة خلفية أو `store_requests`).
class StoreRequest {
  StoreRequest({
    required this.id,
    required this.applicantId,
    required this.storeName,
    required this.phone,
    required this.category,
    required this.status,
    this.description,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.rejectionReason,
    this.storeId,
  });

  final String id;
  final String applicantId;
  final String storeName;
  final String phone;
  final String category;
  final String status;
  final String? description;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? rejectionReason;
  final String? storeId;

  static DateTime? _parseReviewedAt(dynamic reviewedTs) {
    if (reviewedTs == null) return null;
    try {
      final sec = (reviewedTs as dynamic).seconds;
      if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } on Object {
      return DateTime.tryParse(reviewedTs.toString());
    }
    return DateTime.tryParse(reviewedTs.toString());
  }

  factory StoreRequest.fromMap(String id, Map<String, dynamic> d) {
    final reviewedTs = d['reviewedAt'];
    return StoreRequest(
      id: id,
      applicantId: (d['applicantId'] ?? d['ownerId'] ?? '').toString(),
      storeName: (d['storeName'] ?? d['name'] ?? '').toString(),
      phone: (d['phone'] ?? '').toString(),
      category: (d['category'] ?? '').toString(),
      status: (d['status'] ?? 'pending').toString(),
      description: d['description']?.toString(),
      reviewedBy: d['reviewedBy']?.toString(),
      reviewedAt: _parseReviewedAt(reviewedTs),
      reviewNote: d['reviewNote']?.toString(),
      rejectionReason: d['rejectionReason']?.toString(),
      storeId: d['storeId']?.toString(),
    );
  }
}
