import 'package:flutter/material.dart';

/// يلف محتوى تبويب شريط التنقل السفلي مع [AutomaticKeepAliveClientMixin].
/// يُستخدم مع [IndexedStack] في [MainNavigationPage] لضمان بقاء الحالة عند التبديل.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
