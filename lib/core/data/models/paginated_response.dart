/// Cursor-based page from the backend catalog / orders APIs.
class PaginatedResponse<T> {
  PaginatedResponse({
    required this.data,
    this.nextCursor,
  });

  final List<T> data;
  final String? nextCursor;
}
