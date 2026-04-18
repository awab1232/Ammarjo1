// تحذير (Flutter Web): أخطاء تحميل صور Storage غالباً CORS على الـ bucket — راجع تعليق [AmmarCachedImage.fixUrl].
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// إزالة query string لإعادة التحميل بعد فشل [CachedNetworkImage] (نفس الملف فقط).
String _stripUrlQuery(String url) {
  final i = url.indexOf('?');
  if (i < 0) return url;
  return url.substring(0, i);
}

/// محاولة ثانية بعد فشل التحميل: الرابط الأساسي بدون معاملات + `alt=media` صراحةً (تجريبي — مناسب لروابط Firebase Storage).
String experimentalRetryUrlStripQueryAndAltMedia(String originalUrl) {
  final base = _stripUrlQuery(originalUrl.trim());
  if (base.isEmpty) return base;
  return '$base?alt=media';
}

/// صورة شبكة مع تخزين مؤقت؛ [BoxFit.contain] وافتراضياً وأيقونة ورشة/مستودع عند الفشل أو الغياب.
///
/// [productTileStyle]: رؤوس طلبات وتلميح أخطاء مناسب لصور منتجات Firebase/الشبكة.
///
/// **محاولتان للتحميل:** (1) الرابط بعد [fixUrl] (2) إن فشلت: الرابط بدون query + `?alt=media` — انظر [experimentalRetryUrlStripQueryAndAltMedia].
class AmmarCachedImage extends StatelessWidget {
  const AmmarCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.httpHeaders,
    this.productTileStyle = false,
    this.useShimmerPlaceholder = false,
  });

  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Map<String, String>? httpHeaders;
  final bool productTileStyle;

  /// When true, shows a shimmer block instead of a spinner while the image loads (hero banners, large tiles).
  final bool useShimmerPlaceholder;

  static const Map<String, String> kProductImageHeaders = {'Accept': 'image/*'};

  /// تطبيع روابط التخزين: إضافة `alt=media` عند الحاجة، ودعم نطاقات Firebase Storage الشائعة.
  /// على الويب، فشل التحميل رغم الرابط الصحيح غالباً بسبب CORS — انظر تعليق الملف أعلى [AmmarCachedImage].
  static String fixUrl(String url) {
    final t = url.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    // روابط Google Cloud Storage / Firebase Storage الشائعة (قد تُعرض بدون alt=media).
    final looksLikeFirebaseOrGcsStorage = lower.contains('firebasestorage.googleapis.com') ||
        lower.contains('storage.googleapis.com') ||
        lower.contains('firebasestorage.app') ||
        lower.contains('googleapis.com/v0/b/');
    if (looksLikeFirebaseOrGcsStorage && !t.contains('alt=media')) {
      final sep = t.contains('?') ? '&' : '?';
      return '$t${sep}alt=media';
    }
    return t;
  }

  static Widget placeholder(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF0F1F4),
      child: Center(
        child: Icon(Icons.warehouse_outlined, color: AppColors.orange.withValues(alpha: 0.42), size: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AmmarCachedImageImpl(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: httpHeaders,
      productTileStyle: productTileStyle,
      useShimmerPlaceholder: useShimmerPlaceholder,
    );
  }
}

class _AmmarCachedImageImpl extends StatefulWidget {
  const _AmmarCachedImageImpl({
    required this.imageUrl,
    required this.fit,
    this.width,
    this.height,
    this.httpHeaders,
    required this.productTileStyle,
    required this.useShimmerPlaceholder,
  });

  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Map<String, String>? httpHeaders;
  final bool productTileStyle;
  final bool useShimmerPlaceholder;

  @override
  State<_AmmarCachedImageImpl> createState() => _AmmarCachedImageImplState();
}

class _AmmarCachedImageImplState extends State<_AmmarCachedImageImpl> {
  /// 0 = المحاولة الأولى ([fixUrl])، 1 = المحاولة الثائية (بدون query + ?alt=media).
  int _loadPhase = 0;

  @override
  void didUpdateWidget(covariant _AmmarCachedImageImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadPhase = 0;
    }
  }

  String _effectiveUrlForPhase(String raw) {
    if (_loadPhase == 0) {
      return AmmarCachedImage.fixUrl(raw);
    }
    // المحاولة الثانية بعد الفشل: استخراج الأساس وفرض alt=media (تجريبي).
    return experimentalRetryUrlStripQueryAndAltMedia(raw);
  }

  void _logLoadFailure(String attemptedUrl, Object error, StackTrace? stack) {
    debugPrint(
      '[AmmarCachedImage] LOAD FAILED url="$attemptedUrl" phase=$_loadPhase error=$error',
    );
    if (stack != null && kDebugMode) {
      debugPrint('[AmmarCachedImage] stack: $stack');
    }
  }

  Widget _buildFinalErrorUi(BuildContext context) {
    final bg = widget.productTileStyle ? Colors.grey[200]! : const Color(0xFFF0F1F4);
    return ColoredBox(
      color: bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.grey[600], size: widget.productTileStyle ? 32 : 40),
              const SizedBox(height: 6),
              Text(
                'فشل تحميل الصورة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: widget.productTileStyle ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingPlaceholder(BuildContext context) {
    if (widget.productTileStyle) {
      return ColoredBox(
        color: Colors.grey[200]!,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B00)),
          ),
        ),
      );
    }
    if (widget.useShimmerPlaceholder) {
      return Shimmer.fromColors(
        baseColor: const Color(0xFFE6E8EC),
        highlightColor: const Color(0xFFF2F4F7),
        period: const Duration(milliseconds: 1100),
        child: ColoredBox(
          color: const Color(0xFFE6E8EC),
          child: SizedBox(width: widget.width, height: widget.height),
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFFF0F1F4),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = (widget.imageUrl ?? '').trim();
    if (raw.isEmpty) {
      return AmmarCachedImage.placeholder(context);
    }

    final effectiveUrl = _effectiveUrlForPhase(raw);

    final headers = widget.httpHeaders ??
        (widget.productTileStyle
            ? const <String, String>{
                'Accept': 'image/*',
                'Cache-Control': 'no-cache',
              }
            : const <String, String>{
                'Cache-Control': 'no-cache',
              });

    return CachedNetworkImage(
      key: ValueKey<String>('ammar-img-$raw-$_loadPhase'),
      imageUrl: effectiveUrl,
      httpHeaders: headers,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: const Duration(milliseconds: 220),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (context, _) => _loadingPlaceholder(context),
      errorWidget: (context, failedUrl, error) {
        _logLoadFailure(failedUrl, error, null);

        if (_loadPhase == 0) {
          final firstTry = AmmarCachedImage.fixUrl(raw);
          final secondTry = experimentalRetryUrlStripQueryAndAltMedia(raw);
          // إذا كانت المحاولة الثانية مطابقة للأولى لا فائدة من إعادة الطلب (تفادٍ لحلقة لا نهائية).
          if (secondTry != firstTry) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _loadPhase = 1);
              }
            });
          } else {
            return _buildFinalErrorUi(context);
          }
          return widget.productTileStyle
              ? ColoredBox(
                  color: Colors.grey[200]!,
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B00)),
                    ),
                  ),
                )
              : ColoredBox(
                  color: const Color(0xFFF0F1F4),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange.withValues(alpha: 0.7)),
                    ),
                  ),
                );
        }

        return _buildFinalErrorUi(context);
      },
    );
  }
}
