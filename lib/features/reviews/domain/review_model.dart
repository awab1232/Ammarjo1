class ReviewReply {
  const ReviewReply({
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  factory ReviewReply.fromMap(Map<String, dynamic> map) {
    final ts = map['createdAt'];
    return ReviewReply(
      authorId: (map['authorId'] ?? '').toString(),
      authorName: (map['authorName'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      createdAt: ts is DateTime
          ? ts
          : (ts is String ? (DateTime.tryParse(ts)?.toLocal() ?? DateTime.now()) : DateTime.now()),
    );
  }
}

class ReviewModel {
  const ReviewModel({
    required this.id,
    required this.targetId,
    required this.targetType,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.images,
    required this.createdAt,
    required this.updatedAt,
    required this.isEdited,
    required this.likes,
    required this.replies,
  });

  final String id;
  final String targetId;
  final String targetType; // product | store | wholesaler
  final String userId;
  final String userName;
  final double rating;
  final String comment;
  final List<String> images;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isEdited;
  final int likes;
  final List<ReviewReply> replies;

  factory ReviewModel.fromBackendMap(Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is DateTime) return raw;
      if (raw is String) {
        return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    final createdAtRaw = data['createdAt'] ?? data['created_at'];
    final updatedAtRaw = data['updatedAt'] ?? data['updated_at'] ?? createdAtRaw;
    final repliesRaw = data['replies'];
    final parsedReplies = <ReviewReply>[];
    if (repliesRaw is List) {
      for (final row in repliesRaw) {
        if (row is Map) {
          parsedReplies.add(ReviewReply.fromMap(Map<String, dynamic>.from(row)));
        }
      }
    }

    final imagesRaw = data['images'];
    final parsedImages = <String>[];
    if (imagesRaw is List) {
      for (final image in imagesRaw) {
        final text = image.toString().trim();
        if (text.isNotEmpty) parsedImages.add(text);
      }
    }
    return ReviewModel(
      id: (data['id'] ?? '').toString(),
      targetId: (data['targetId'] ?? data['target_id'] ?? '').toString(),
      targetType: (data['targetType'] ?? data['target_type'] ?? '').toString(),
      userId: (data['userId'] ?? data['reviewerId'] ?? data['reviewer_id'] ?? '').toString(),
      userName: (data['userName'] ?? data['reviewerName'] ?? 'مستخدم').toString(),
      rating: (data['rating'] is num) ? (data['rating'] as num).toDouble() : 0.0,
      comment: (data['comment'] ?? data['reviewText'] ?? data['review_text'] ?? '').toString(),
      images: parsedImages,
      createdAt: parseDate(createdAtRaw),
      updatedAt: parseDate(updatedAtRaw),
      isEdited: data['isEdited'] == true,
      likes: (data['likes'] is num) ? (data['likes'] as num).toInt() : 0,
      replies: parsedReplies,
    );
  }
}

class RatingAggregate {
  const RatingAggregate({
    required this.averageRating,
    required this.totalReviews,
  });

  final double averageRating;
  final int totalReviews;

  factory RatingAggregate.fromBackendMap(Map<String, dynamic> map) {
    return RatingAggregate(
      averageRating: (map['avgRating'] is num)
          ? (map['avgRating'] as num).toDouble()
          : ((map['averageRating'] is num) ? (map['averageRating'] as num).toDouble() : 0.0),
      totalReviews: (map['totalReviews'] is num)
          ? (map['totalReviews'] as num).toInt()
          : ((map['reviewCount'] is num) ? (map['reviewCount'] as num).toInt() : 0),
    );
  }
}
