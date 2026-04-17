class WholesalerRequestModel {
  const WholesalerRequestModel({
    required this.requestId,
    required this.applicantId,
    required this.applicantEmail,
    required this.applicantPhone,
    required this.wholesalerName,
    required this.description,
    required this.category,
    required this.city,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });

  final String requestId;
  final String applicantId;
  final String applicantEmail;
  final String applicantPhone;
  final String wholesalerName;
  final String description;
  final String category;
  final String city;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  factory WholesalerRequestModel.fromBackendMap(Map<String, dynamic> data) {
    final reviewed = data['reviewedAt'];
    return WholesalerRequestModel(
      requestId: (data['id'] ?? data['requestId'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      applicantId: (data['applicantId'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      applicantEmail: (data['applicantEmail'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      applicantPhone: (data['applicantPhone'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      wholesalerName: (data['wholesalerName'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      description: (data['description'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      category: (data['category'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      city: (data['city'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      status: (data['status'] ?? 'pending').toString(),
      reviewedBy: data['reviewedBy']?.toString(),
      reviewedAt: reviewed is String ? DateTime.tryParse(reviewed)?.toLocal() : null,
      rejectionReason: data['rejectionReason']?.toString(),
    );
  }
}
