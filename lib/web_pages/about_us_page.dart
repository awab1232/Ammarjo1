import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/beta_launch_config.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  static final _bodyStyle = GoogleFonts.tajawal(height: 1.7, fontSize: 15);
  static final _sectionTitleStyle = GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('من نحن')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'نحن في Ammarjo نقدم منصة متكاملة تهدف إلى تسهيل قطاع البناء من خلال ربط جميع الأطراف في مكان واحد. نعمل على توفير تجربة ذكية وسهلة للمستخدمين، تجمع بين متاجر مواد البناء، الفنيين المتخصصين، وسوق للمواد المستعملة، لتلبية جميع احتياجات مشاريع البناء والتشطيب.',
              style: _bodyStyle,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            Text(
              'نسعى إلى تبسيط رحلة البناء عبر تقديم حلول عملية وموثوقة، حيث يمكن للمستخدمين الوصول إلى أفضل الموردين، التواصل مع فنيين محترفين، ومقارنة الخيارات بسهولة، مما يوفر الوقت والجهد والتكلفة.',
              style: _bodyStyle,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            Text(
              'كما نوفر في Ammarjo مساعدًا ذكيًا يعتمد على تقنيات الذكاء الاصطناعي، لمساعدة المستخدمين في اتخاذ قرارات أفضل، وتقديم إرشادات ونصائح متخصصة في مختلف مراحل البناء.',
              style: _bodyStyle,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 24),
            Text('🎯 رؤيتنا', style: _sectionTitleStyle, textAlign: TextAlign.right),
            const SizedBox(height: 8),
            Text(
              'أن نكون المنصة الرقمية الأولى في مجال خدمات البناء، من خلال الابتكار وتقديم حلول متكاملة تلبي احتياجات السوق.',
              style: _bodyStyle,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 20),
            Text('🚀 مهمتنا', style: _sectionTitleStyle, textAlign: TextAlign.right),
            const SizedBox(height: 8),
            Text(
              'تمكين الأفراد والمقاولين من إنجاز مشاريعهم بسهولة وكفاءة، عبر توفير أدوات ذكية وخدمات موثوقة في مكان واحد.',
              style: _bodyStyle,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 20),
            Text('⭐ ما يميزنا', style: _sectionTitleStyle, textAlign: TextAlign.right),
            const SizedBox(height: 8),
            ..._bullets(const [
              'ربط متاجر مواد البناء بالمستخدمين مباشرة',
              'توفير فنيين متخصصين في مختلف المجالات',
              'سوق متكامل للمواد المستعملة',
              'مساعد ذكي لدعم قرارات البناء',
              'تجربة استخدام سهلة وسريعة',
            ]),
            if (BetaLaunchConfig.feedbackUrl.trim().isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('نسخة تجريبية — ملاحظاتك تهمنا', style: _sectionTitleStyle, textAlign: TextAlign.right),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(BetaLaunchConfig.feedbackUrl.trim());
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.feedback_outlined),
                label: Text(
                  'إرسال ملاحظة للفريق',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Iterable<Widget> _bullets(List<String> items) sync* {
    for (final line in items) {
      yield Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: TextDirection.rtl,
          children: [
            Text('• ', style: _bodyStyle),
            Expanded(child: Text(line, style: _bodyStyle, textAlign: TextAlign.right)),
          ],
        ),
      );
    }
  }
}
