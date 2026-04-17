import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> sentryCaptureExceptionSafe(
  dynamic error, {
  StackTrace? stackTrace,
  ScopeCallback? withScope,
}) async {
  try {
    await Sentry.captureException(error, stackTrace: StackTrace.current, withScope: withScope);
  } on Object {
    return;
  }
}

Future<void> sentryCaptureMessageSafe(
  String message, {
  SentryLevel level = SentryLevel.info,
  ScopeCallback? withScope,
}) async {
  try {
    await Sentry.captureMessage(message, level: level, withScope: withScope);
  } on Object {
    return;
  }
}

Future<void> sentryConfigureScopeSafe(ScopeCallback callback) async {
  try {
    await Sentry.configureScope(callback);
  } on Object {
    return;
  }
}

