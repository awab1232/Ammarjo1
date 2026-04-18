import 'dart:async';

/// يلف [source] بحيث يُطبَّق [TimeoutException] فقط إذا لم يصل **أي** حدث خلال [timeout].
/// بعد أول حدث يُلغى المؤقت ويُمرَّر باقي الأحداث دون قيود زمنية بين الحدث والآخر.
///
/// يستخدم `StreamSubscription?` ويُلغى عند الإلغاء — لتجنّب [LateInitializationError] مع `late`.
Stream<T> streamWithFirstEventTimeout<T>(
  Stream<T> source, {
  Duration timeout = const Duration(seconds: 90),
  String timeoutMessage = 'انتهت مهلة التحميل',
}) {
  return Stream<T>.multi((controller) {
    var got = false;
    StreamSubscription<T>? sub;
    Timer? timer;

    void cancelTimer() {
      timer?.cancel();
      timer = null;
    }

    try {
      sub = source.listen(
        (data) {
          got = true;
          cancelTimer();
          if (!controller.isClosed) controller.add(data);
        },
        onError: (Object e, StackTrace st) {
          cancelTimer();
          if (!controller.isClosed) controller.addError(e, st);
        },
        onDone: () {
          cancelTimer();
          if (!controller.isClosed) controller.close();
        },
        cancelOnError: false,
      );
    } on Object {
      if (!controller.isClosed) {
        controller.addError('unexpected error', StackTrace.current);
        controller.close();
      }
      return;
    }

    timer = Timer(timeout, () {
      if (!got && !controller.isClosed) {
        sub?.cancel();
        if (!controller.isClosed) {
          controller.addError(TimeoutException(timeoutMessage));
          controller.close();
        }
      }
    });

    controller.onCancel = () {
      cancelTimer();
      sub?.cancel();
    };
  });
}
