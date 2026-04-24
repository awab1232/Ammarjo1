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
      requestId: (data['id'] ?? data['requestId'] ?? '').toString(),
      applicantId: (data['applicantId'] ?? '').toString(),
      applicantEmail: (data['applicantEmail'] ?? '').toString(),
      applicantPhone: (data['applicantPhone'] ?? '').toString(),
      wholesalerName: (data['wholesalerName'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      reviewedBy: data['reviewedBy']?.toString(),
      reviewedAt: reviewed is String ? DateTime.tryParse(reviewed)?.toLocal() : null,
      rejectionReason: data['rejectionReason']?.toString(),
    );
  }
}
