import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// مسارات التخزين المستخدمة في التطبيق: `admin/*`, `products/*`, `stores/{storeId}/*`.
abstract final class StorageService {
  StorageService._();

  static FirebaseStorage get _storage => FirebaseStorage.instance;

  static String _contentTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/jpeg';
  }

  static String _safeFileName(String fileName) => fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');

  static Future<String> uploadBytes({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final ref = _storage.ref().child(path);
    final ct = contentType ?? _contentTypeForFileName(path);
    await ref.putData(bytes, SettableMetadata(contentType: ct, cacheControl: 'public, max-age=31536000'));
    final url = await ref.getDownloadURL();
    if (url.contains('alt=media')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}alt=media';
  }

  static Future<String> uploadAdminProductImage(Uint8List bytes, String fileName) {
    final safe = _safeFileName(fileName);
    return uploadBytes(path: 'admin/products/$safe', bytes: bytes);
  }

  static Future<String> uploadAdminTechnicianPhoto(Uint8List bytes, String fileName) {
    final safe = _safeFileName(fileName);
    return uploadBytes(path: 'admin/technicians/$safe', bytes: bytes);
  }

  static Future<String> uploadAdminCategoryImage(Uint8List bytes, String fileName) {
    final safe = _safeFileName(fileName);
    return uploadBytes(path: 'admin/categories/$safe', bytes: bytes);
  }

  static Future<String> uploadAdminHomeBannerImage(Uint8List bytes, String fileName) {
    final safe = _safeFileName(fileName);
    return uploadBytes(path: 'admin/home_banners/$safe', bytes: bytes);
  }

  /// استيراد CSV / كتالوج — يطابق [csv_product_importer] (`products/...`).
  static Future<String> uploadCatalogProductImage(Uint8List bytes, String fileName) {
    final safe = _safeFileName(fileName);
    return uploadBytes(path: 'products/$safe', bytes: bytes);
  }

  /// متجر المالك — يطابق [StoreOwnerRepository.uploadProductImages].
  static Future<String> uploadStoreProductImage({
    required String storeId,
    required String productId,
    required int index,
    required Uint8List bytes,
  }) {
    return uploadBytes(
      path: 'stores/$storeId/products/$productId/img_$index.jpg',
      bytes: bytes,
      contentType: 'image/jpeg',
    );
  }

  /// متجر المالك — يطابق [StoreOwnerRepository.uploadOfferImage].
  static Future<String> uploadStoreOfferImage({
    required String storeId,
    required String objectFileName,
    required Uint8List bytes,
  }) {
    return uploadBytes(
      path: 'stores/$storeId/offers/$objectFileName',
      bytes: bytes,
      contentType: 'image/jpeg',
    );
  }

  static Future<String> downloadUrlForPath(String path) => _storage.ref().child(path).getDownloadURL();

  static Future<void> deletePath(String path) => _storage.ref().child(path).delete();
}
