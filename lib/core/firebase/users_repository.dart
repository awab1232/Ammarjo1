import '../../features/store/domain/favorite_product.dart';
import '../../features/store/domain/models.dart';
import '../contracts/feature_state.dart';
import '../data/repositories/user_repository.dart';
import '../services/user_service.dart';

/// Legacy static facade kept for compatibility; backed by backend APIs.
abstract final class UsersRepository {
  static final UserRepository _repo = BackendUserRepository.instance;

  static CustomerProfile? customerProfileFromUserDocData(Map<String, dynamic>? d) =>
      UserService.instance.customerProfileFromMap(d);

  static Future<CustomerProfile?> fetchProfileDocument(String uid) => _repo.fetchProfileDocument(uid);

  static Future<void> syncUserDocument(CustomerProfile profile) => _repo.syncUserDocument(profile);

  static Future<void> incrementPoints(String uid, int amount) => _repo.incrementPoints(uid, amount);

  static Future<void> addPointsForOrder({
    required String userId,
    required int points,
    required String orderId,
  }) =>
      _repo.addPointsForOrder(userId: userId, points: points, orderId: orderId);

  static Future<void> addToFavorites(
    String userId,
    String productId, {
    required String productName,
    required String productImage,
    required double productPrice,
  }) =>
      _repo.addToFavorites(
        userId,
        productId,
        productName: productName,
        productImage: productImage,
        productPrice: productPrice,
      );

  static Future<void> removeFromFavorites(String userId, String productId) =>
      _repo.removeFromFavorites(userId, productId);

  static Future<bool> isFavorite(String userId, String productId) =>
      _repo.isFavorite(userId, productId);

  static Stream<FeatureState<List<FavoriteProduct>>> watchFavorites(String userId) =>
      _repo.watchFavorites(userId);

  static Future<void> migrateFavoritesToBackend({
    required String userId,
    required Set<int> localIds,
    required Product? Function(int productId) resolveProduct,
  }) =>
      _repo.migrateFavoritesToBackend(
        userId: userId,
        localIds: localIds,
        resolveProduct: resolveProduct,
      );
}
