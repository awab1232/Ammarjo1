import 'package:flutter/material.dart';

/// مفتاح [Navigator] الجذر — يُستخدم عند الحاجة لعرض حوار من دون [BuildContext] في الخدمات.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
