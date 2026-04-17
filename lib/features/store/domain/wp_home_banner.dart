/// شريحة بانر من ووردبريس (صورة بارزة + رابط المقال اختياري).
class WpHomeBannerSlide {
  const WpHomeBannerSlide({
    required this.imageUrl,
    this.linkUrl,
    this.title,
  });

  final String imageUrl;
  final String? linkUrl;
  final String? title;
}
