import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// نوع MIME من امتداد الملف — يُعرَّف بشكل صحيح حتى تعرض المتصفحات/الـ CDN الصورة ولا تُرفض.
String _contentTypeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return 'image/jpeg';
}

/// رفع صور لوحة الأدمن (منتجات / فنيين) إلى Firebase Storage.
abstract final class AdminStorageService {
  static Future<String> _downloadUrlWithAlt(Reference ref) async {
    final url = await ref.getDownloadURL();
    if (url.contains('alt=media')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}alt=media';
  }

  static Future<String> uploadProductImage(Uint8List bytes, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ref = FirebaseStorage.instance.ref().child('admin/products/$safe');
    final ct = _contentTypeForFileName(safe);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'),
    );
    return _downloadUrlWithAlt(ref);
  }

  static Future<String> uploadTechnicianPhoto(Uint8List bytes, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ref = FirebaseStorage.instance.ref().child('admin/technicians/$safe');
    final ct = _contentTypeForFileName(safe);
    await ref.putData(bytes, SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'));
    return _downloadUrlWithAlt(ref);
  }

  static Future<String> uploadCategoryImage(Uint8List bytes, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ref = FirebaseStorage.instance.ref().child('admin/categories/$safe');
    final ct = _contentTypeForFileName(safe);
    await ref.putData(bytes, SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'));
    return _downloadUrlWithAlt(ref);
  }

  static Future<String> uploadHomeBannerImage(Uint8List bytes, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ref = FirebaseStorage.instance.ref().child('admin/home_banners/$safe');
    final ct = _contentTypeForFileName(safe);
    await ref.putData(bytes, SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'));
    return _downloadUrlWithAlt(ref);
  }

  static Future<String> uploadTechSpecialtyImage(Uint8List bytes, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ref = FirebaseStorage.instance.ref().child('admin/tech_specialties/$safe');
    final ct = _contentTypeForFileName(safe);
    await ref.putData(bytes, SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'));
    return _downloadUrlWithAlt(ref);
  }

  static Future<String> uploadStoreCategoryImage(Uint8List bytes, String fileName) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final ref = FirebaseStorage.instance.ref().child('admin/store_categories/$safe');
    final ct = _contentTypeForFileName(safe);
    await ref.putData(bytes, SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'));
    return _downloadUrlWithAlt(ref);
  }
}
