import 'dart:developer' as developer;
import 'dart:async';

import 'core/session/backend_identity_controller.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/config/backend_orders_config.dart';
import 'core/contracts/feature_contract_validator.dart';
import 'core/security/build_integrity_marker.dart';
import 'core/security/firestore_killer.dart';
import 'core/security/runtime_safety_enforcer.dart';
import 'core/widgets/backend_dev_fallback_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/data/repositories/order_repository.dart';
import 'core/data/repositories/product_repository.dart';
import 'core/data/repositories/store_repository.dart';
import 'core/data/repositories/user_repository.dart';
import 'firebase_options.dart';
import 'features/maintenance/presentation/maintenance_controller.dart';
import 'web_pages/about_us_page.dart';
import 'web_pages/blog_page.dart';
import 'web_pages/privacy_policy_page.dart';
import 'web_pages/return_policy_page.dart';
import 'web_pages/terms_of_use_page.dart';
import 'core/config/gemini_config.dart';
import 'core/startup/staging_startup_guard.dart';
import 'core/firebase/app_check_bootstrap.dart';
import 'core/firebase/fcm_bootstrap.dart';
import 'core/firebase/local_chat_notification_service.dart';
import 'core/services/gemini_ai_service.dart';
import 'core/services/firebase_backend_session_service.dart';
import 'core/navigation/app_navigator.dart';
import 'core/seo/seo_indexing_hooks.dart';
import 'core/seo/organic_traffic_system.dart';
import 'core/seo/seo_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/ammarjo_splash_screen.dart';
import 'features/store/data/failed_mirror_orders_worker.dart';
import 'features/store/domain/models.dart';
import 'features/store/presentation/pages/product_details_page.dart';
import 'features/store/presentation/store_controller.dart';
import 'features/store/presentation/pages/main_navigation_page.dart';
import 'features/stores/presentation/stores_list_page.dart';
import 'core/monitoring/sentry_safe.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    if (kDebugMode) {
      developer.log(
        'FCM background message received',
        name: 'FCM',
        error: message.messageId,
      );
    }
  } on Object {
    if (kDebugMode) {
      developer.log('FCM background handler failed');
    }
  }
}

/// Sentry DSN is loaded only from dart-define (never hardcoded), e.g.:
/// flutter run --dart-define=SENTRY_DSN=https://8f6710a4cc2492c6ac6414329b8fb028@o4511219698237440.ingest.de.sentry.io/4511219712655440
Future<void> main() async {
  // ignore: avoid_print
  print('APP START');
  final sentryDsn = const String.fromEnvironment('SENTRY_DSN', defaultValue: '').trim();
  final appEnv = const String.fromEnvironment('APP_ENV', defaultValue: '').trim();
  final resolvedEnv = appEnv.isNotEmpty ? appEnv : (kDebugMode ? 'staging' : 'production');
  final tracesSampleRate = resolvedEnv == 'production' ? 0.1 : 1.0;
  Future<void> runner() async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FLUTTER ERROR: ${details.exception}');
      unawaited(
        sentryCaptureExceptionSafe(
          details.exception,
          stackTrace: details.stack,
        ),
      );
    };
    await runZonedGuarded<Future<void>>(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await _appMain();
    }, (error, stack) async {
      debugPrint('UNCAUGHT ERROR: $error');
      await sentryCaptureExceptionSafe(error, stackTrace: stack);
    });
  }
  if (sentryDsn.isEmpty) {
    if (kDebugMode) {
      debugPrint('[Sentry] WARNING: SENTRY_DSN is empty. App will continue without Sentry.');
    }
    await runner();
    return;
  }
  try {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = tracesSampleRate;
        options.environment = resolvedEnv;
      },
      appRunner: () async {
        await runner();
      },
    );
  } on Object {
    await runner();
  }
}

Future<void> _appMain() async {
  try {
    BackendOrdersConfig.enforceStartupSafetyOrThrow();
  } on Object catch (e, st) {
    debugPrint('[Startup] backend config validation failed (continuing): $e');
    if (kDebugMode) {
      developer.log('BackendOrdersConfig.enforceStartupSafetyOrThrow failed', error: e, stackTrace: st);
    }
  }
  try {
    FeatureContractValidator.validateAtStartup();
  } on Object catch (e, st) {
    debugPrint('[Startup] feature contract validation failed (continuing): $e');
    if (kDebugMode) {
      developer.log('FeatureContractValidator.validateAtStartup failed', error: e, stackTrace: st);
    }
  }
  ensureFirestorePolicyHookLoaded();
  assert(PRODUCTION_HARDENED, 'build_integrity_marker');
  await RuntimeSafetyEnforcer.probeBackendHealthNonBlocking().onError((_, _) => null);
  await StagingStartupGuard.verifyOrThrow().onError((_, _) => null);
  final info = await PackageInfo.fromPlatform();
  await sentryConfigureScopeSafe((scope) {
    scope.setTag('app_version', info.version);
    scope.setTag('platform', kIsWeb ? 'web' : defaultTargetPlatform.name);
    scope.setTag('build_mode', kDebugMode ? 'debug' : 'release');
  });
  // تخزين مؤقت للصور: يقلل إعادة التحميل عند التنقل.
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20; // 80 MiB
  debugPrint('🚀 App starting...');
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  // تهيئة Firebase فقط (Firestore / Storage / إلخ) — بدون جلسة Auth مطلوبة لشاشة الدخول الحالية.
  // تجنّب [core/duplicate-app] عند Hot Restart أو عند وجود تهيئة سابقة من المنصّة/العزل الخلفي.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // ignore: avoid_print
      print('FIREBASE OK');
      debugPrint('✅ Firebase initialized');
    } else {
      // ignore: avoid_print
      print('FIREBASE OK');
      debugPrint('✅ Firebase already initialized (${Firebase.apps.length} app(s))');
    }
    if (Firebase.apps.isNotEmpty && kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      SeoIndexingHooks.start();
      OrganicTrafficSystem.instance.start();
    }
    if (Firebase.apps.isNotEmpty) {
      refreshGeminiApiKeyAtStartup();
      clearGeminiGenerativeModelCache();
      await activateFirebaseAppCheck();
    }
  } on Object {
    debugPrint('❌ Firebase init error');
    if (kDebugMode) {
      developer.log('Firebase.initializeApp failed');
    }
  }
  // Firestore caching لتحسين السرعة والثبات عند ضعف/انقطاع الشبكة.
  try {
  } on Object {
    if (kDebugMode) {
      developer.log('Firestore initialization failed');
    }
  }
  if (Firebase.apps.isNotEmpty) {
    FailedMirrorOrdersWorker.start();
  }
  BackendOrdersConfig.warnIfBackendBaseUrlMissing('app_startup');
  if (Firebase.apps.isNotEmpty) {
    FirebaseAuth.instance.authStateChanges().listen((User? u) async {
      final c = BackendIdentityController.instance;
      if (u != null) {
        try {
          await FirebaseBackendSessionService.syncWithBackend(firebaseUser: u);
        } on Object {
          // Best effort: keep Firebase session alive even if backend sync is temporarily down.
        }
        await c.refresh();
      } else {
        await FirebaseBackendSessionService.clear().onError((_, _) => null);
        c.clear();
      }
    });
    final cur = FirebaseAuth.instance.currentUser;
    if (cur != null) {
      unawaited(FirebaseBackendSessionService.restoreAndSyncIfNeeded());
      unawaited(BackendIdentityController.instance.refresh());
    }
  }
  // إشعارات محلية + ربط FCM: منصات غير الويب فقط (انظر LocalChatNotificationService).
  try {
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      await FcmBootstrap.registerIfSignedIn();
      FirebaseMessaging.onMessage.listen((message) {
        if (kDebugMode) {
          developer.log(
            'FCM foreground message',
            name: 'FCM',
            error: message.data.toString(),
          );
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (kDebugMode) {
          developer.log(
            'FCM message opened app',
            name: 'FCM',
            error: message.messageId,
          );
        }
      });
      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        developer.log('FCM token registered', name: 'FCM', error: token);
      }
      FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null) {
          FcmBootstrap.registerIfSignedIn();
          sentryConfigureScopeSafe((scope) {
            scope.setUser(SentryUser(id: u.uid, email: u.email));
          });
        } else {
          sentryConfigureScopeSafe((scope) {
            scope.setUser(null);
          });
        }
      });
      await LocalChatNotificationService.init();
      LocalChatNotificationService.bindAuthState();
    }
  } on Object {
    if (kDebugMode) {
      developer.log('LocalChatNotificationService init failed');
    }
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final store = StoreController();
            store.bootstrap();
            return store;
          },
        ),
        ChangeNotifierProvider(
          create: (c) => c.read<StoreController>().catalog,
        ),
        ChangeNotifierProvider(create: (c) => c.read<StoreController>().search),
        ChangeNotifierProvider(create: (c) => c.read<StoreController>().filter),
        ChangeNotifierProvider(
          create: (c) => c.read<StoreController>().cartState,
        ),
        ChangeNotifierProvider(create: (c) => c.read<StoreController>().user),
        ChangeNotifierProvider<BackendIdentityController>.value(
          value: BackendIdentityController.instance,
        ),
        ChangeNotifierProvider(create: (_) => MaintenanceController()..load()),
        Provider<ProductRepository>(create: (_) => BackendProductRepository.instance),
        Provider<OrderRepository>(create: (_) => BackendOrderRepository.instance),
        Provider<UserRepository>(create: (_) => BackendUserRepository.instance),
        Provider<StoreRepository>(create: (_) => RestStoreRepository.instance),
      ],
      child: const AmmarStoreApp(),
    ),
  );
  if (const bool.fromEnvironment('SENTRY_TEST_FLUTTER', defaultValue: false)) {
    Future<void>.microtask(() {
      throw Exception('SENTRY_TEST_FLUTTER');
    });
  }
}

class AmmarStoreApp extends StatelessWidget {
  const AmmarStoreApp({super.key});

  /// Default UI language (fixes missing MaterialLocalizations when set with delegates below).
  static const Locale _defaultLocale = Locale('ar');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'AmmarJo',
      debugShowCheckedModeBanner: false,
      // Default locale: Arabic
      locale: _defaultLocale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supported) {
        if (locale == null) return _defaultLocale;
        for (final l in supported) {
          if (l.languageCode == locale.languageCode) {
            return l;
          }
        }
        return _defaultLocale;
      },
      theme: AmmarJoTheme.light(),
      builder: (context, child) {
        SeoService.apply(SeoService.homeFallback);
        final code = Localizations.localeOf(context).languageCode;
        final rtl = code == 'ar';
        final content = Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
        if (!kDebugMode) return content;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: BackendDevFallbackBanner(),
            ),
          ],
        );
      },
      home: const AmmarJoSplashScreen(),
      routes: {
        '/main': (_) => const MainNavigationPage(),
        '/privacy': (_) => const PrivacyPolicyPage(),
        '/about': (_) => const AboutUsPage(),
        '/terms': (_) => const TermsOfUsePage(),
        '/return-policy': (_) => const ReturnPolicyPage(),
        '/blog': (_) => const BlogPage(),
      },
      onGenerateRoute: (settings) {
        final routeName = settings.name ?? '';
        if (routeName.startsWith('/blog/')) {
          final id = Uri.decodeComponent(
            routeName.replaceFirst('/blog/', '').trim(),
          );
          return MaterialPageRoute<void>(
            builder: (_) => BlogDetailPage(articleId: id.isEmpty ? '1' : id),
            settings: settings,
          );
        }
        if (routeName.startsWith('/product/')) {
          final productId = int.tryParse(
            routeName.replaceFirst('/product/', '').trim(),
          );
          final args = settings.arguments;
          Product? product;
          String? cartStoreId;
          String? cartStoreName;
          if (args is Map) {
            final maybeProduct = args['product'];
            if (maybeProduct is Product) {
              product = maybeProduct;
            }
            cartStoreId = args['cartStoreId']?.toString();
            cartStoreName = args['cartStoreName']?.toString();
          }
          if (product == null && productId != null) {
            final store = appNavigatorKey.currentContext
                ?.read<StoreController>();
            final list = store?.products ?? const <Product>[];
            for (final item in list) {
              if (item.id == productId) {
                product = item;
                break;
              }
            }
          }
          if (product == null) {
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              settings: settings,
            );
          }
          return MaterialPageRoute<void>(
            builder: (_) => ProductDetailsPage(
              product: product!,
              cartStoreId: cartStoreId,
              cartStoreName: cartStoreName,
            ),
            settings: settings,
          );
        }
        if (routeName.startsWith('/category/')) {
          final categoryName = Uri.decodeComponent(
            routeName.replaceFirst('/category/', '').trim(),
          );
          return MaterialPageRoute<void>(
            builder: (_) => StoresListPage(category: categoryName),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
