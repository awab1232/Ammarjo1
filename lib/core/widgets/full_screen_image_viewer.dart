import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.title,
    this.images,
    this.initialIndex = 0,
  });

  final String imageUrl;
  final String? title;
  final List<String>? images;
  final int initialIndex;

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<String> _images;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _images = widget.images ?? <String>[widget.imageUrl];
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: widget.title != null
            ? Text(
                widget.title!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white70),
            onPressed: () => _transformController.value = Matrix4.identity(),
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _images.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (ctx, i) {
              return InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: _images[i],
                    fit: BoxFit.contain,
                    placeholder: (ctx, url) =>
                        const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B00))),
                    errorWidget: (ctx, url, err) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.broken_image, color: Colors.white54, size: 64),
                        SizedBox(height: 8),
                        Text('تعذر تحميل الصورة', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (_images.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentIndex == i ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentIndex == i ? const Color(0xFFFF6B00) : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: _images.length > 1 ? 50 : 20,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                'اضغط مطولاً للتكبير',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void openImageViewer(
  BuildContext context, {
  required String imageUrl,
  String? title,
  List<String>? images,
  int initialIndex = 0,
}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (ctx, animation, _) => FadeTransition(
        opacity: animation,
        child: FullScreenImageViewer(
          imageUrl: imageUrl,
          title: title,
          images: images,
          initialIndex: initialIndex,
        ),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    ),
  );
}
