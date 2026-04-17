import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ReturnPolicyPage extends StatelessWidget {
  const ReturnPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سياسة الاسترجاع')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          '''
سياسة الاستبدال والاسترجاع:

1) المدة:
- يمكن طلب الاسترجاع خلال 14 يوم للسلع الاستهلاكية.
- بعض الفئات قد تمتد حتى 30 يوم وفق شروط المتجر.

2) الشروط:
- أن تكون السلعة بحالتها الأصلية.
- وجود إثبات شراء/رقم الطلب.
- عدم استخدام المنتج بشكل يخرجه من حالة البيع.

3) خطوات تقديم الطلب:
- الدخول إلى "طلباتي".
- اختيار الطلب وتقديم طلب استرجاع.
- متابعة حالة الطلب عبر الإشعارات.

4) الاستثناءات:
- المنتجات المصنوعة خصيصًا.
- المنتجات التالفة بسبب سوء الاستخدام.
''',
          style: GoogleFonts.tajawal(height: 1.7),
          textAlign: TextAlign.right,
        ),
      ),
    );
  }
}
