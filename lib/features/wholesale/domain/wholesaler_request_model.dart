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
      requestId: (data['id'] ?? data['requestId'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      applicantId: (data['applicantId'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      applicantEmail: (data['applicantEmail'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      applicantPhone: (data['applicantPhone'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      wholesalerName: (data['wholesalerName'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      description: (data['description'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      category: (data['category'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      city: (data['city'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      status: (data['status'] ?? 'pending').toString(),
      reviewedBy: data['reviewedBy']?.toString(),
      reviewedAt: reviewed is String ? DateTime.tryParse(reviewed)?.toLocal() : null,
      rejectionReason: data['rejectionReason']?.toString(),
    );
  }
}
