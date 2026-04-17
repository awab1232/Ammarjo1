import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../config/backend_orders_config.dart';
import '../logging/backend_fallback_logger.dart';

/// Debug-only strip when the app is using Firebase (or local) because the backend URL is missing or a fallback was recorded.
class BackendDevFallbackBanner extends StatelessWidget {
  const BackendDevFallbackBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: backendFallbackUiTick,
      builder: (context, _, _) {
        if (!BackendOrdersConfig.shouldShowBackendDevFallbackBanner) {
          return const SizedBox.shrink();
        }
        return Material(
          color: Colors.amber.shade700,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Backend fallback active',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
