class KeywordPlan {
  const KeywordPlan({
    required this.keyword,
    required this.intent,
    required this.articleTitle,
  });
  final String keyword;
  final String intent;
  final String articleTitle;
}

class SocialScript {
  const SocialScript({
    required this.articleSlug,
    required this.tiktok,
    required this.facebook,
    required this.instagram,
  });
  final String articleSlug;
  final String tiktok;
  final String facebook;
  final String instagram;
}

class DailyPlanItem {
  const DailyPlanItem({
    required this.day,
    required this.blogTopic,
    required this.videoIdea,
    required this.platform,
    required this.goal,
  });
  final int day;
  final String blogTopic;
  final String videoIdea;
  final String platform;
  final String goal;
}

class VideoIdea {
  const VideoIdea({
    required this.day,
    required this.hook,
    required this.topic,
    required this.outline,
    required this.cta,
  });
  final int day;
  final String hook;
  final String topic;
  final String outline;
  final String cta;
}

final List<String> _cities = <String>[
  'عمان',
  'إربد',
  'الزرقاء',
  'العقبة',
  'السلط',
  'مادبا',
];

final List<String> _baseKeywords = <String>[
  'مواد بناء',
  'حديد',
  'اسمنت',
  'دهان',
  'سباكة',
  'كهرباء منزلية',
  'أدوات كهربائية',
  'طلب فني',
  'صيانة منزل',
  'تشطيب',
  'عزل اسطح',
  'بلاط',
  'أبواب',
  'مكيفات',
  'أثاث مستعمل',
  'أدوات مستعملة',
  'تاجر جملة',
  'حساب كميات',
  'حاسبة دهان',
  'مناقصة عكسية',
];

final List<KeywordPlan> jordan200Keywords = _buildJordan200Keywords();

List<KeywordPlan> _buildJordan200Keywords() {
  final out = <KeywordPlan>[];
  final intents = <String>['معلوماتي', 'تجاري', 'حل مشكلة', 'مقارنة'];
  var idx = 0;
  for (final city in _cities) {
    for (final base in _baseKeywords) {
      final intent = intents[idx % intents.length];
      final keyword = '$base في $city';
      final title = _titleForIntent(base, city, intent);
      out.add(KeywordPlan(keyword: keyword, intent: intent, articleTitle: title));
      idx++;
      if (out.length == 200) return out;
    }
  }
  while (out.length < 200) {
    final n = out.length + 1;
    final base = _baseKeywords[n % _baseKeywords.length];
    final city = _cities[n % _cities.length];
    out.add(
      KeywordPlan(
        keyword: 'أفضل $base $city 2026',
        intent: 'تجاري',
        articleTitle: 'أفضل خيارات $base في $city لعام 2026 (دليل عملي)',
      ),
    );
  }
  return out;
}

String _titleForIntent(String base, String city, String intent) {
  switch (intent) {
    case 'معلوماتي':
      return 'دليل $base في $city: الأسعار، الأنواع، ونصائح الشراء';
    case 'تجاري':
      return 'أفضل عروض $base في $city وكيف تحصل على سعر أقل';
    case 'حل مشكلة':
      return 'مشاكل $base الشائعة في $city وكيف تحلها خطوة بخطوة';
    default:
      return 'مقارنة شاملة: $base في $city (الجودة مقابل السعر)';
  }
}

final List<Map<String, String>> tenReadyArticles = <Map<String, String>>[
  {
    'slug': 'materials-pricing-amman',
    'title': 'أسعار مواد البناء في عمان: دليل عملي للتوفير',
    'content': '''
## المقدمة
أسعار مواد البناء تتغير باستمرار، ولهذا يحتاج صاحب المشروع إلى طريقة عملية للشراء الذكي.

## الخطوات
1) حدّد الكميات بدقة عبر حاسبة الكميات.
2) قارن 3 عروض على الأقل.
3) اشترِ على دفعات لمنع الهدر.
4) وثّق كل بند وتاريخ الشراء.

## FAQ
س: متى أشتري؟  
ج: عند استقرار السعر أو ظهور عرض موثوق.

س: هل الأرخص أفضل؟  
ج: لا، افحص الجودة أولًا.

## CTA
ابدأ من AmmarJo واطلب عرض سعر خلال دقائق.
'''
  },
  {
    'slug': 'paint-calculator-guide',
    'title': 'طريقة حساب كمية الدهان الصحيحة بدون هدر',
    'content': '''
## المشكلة
الكثير يشتري دهان أكثر من اللازم أو أقل من المطلوب.

## الحل خطوة بخطوة
1) قس المساحة الفعلية.
2) اطرح مساحة الأبواب والنوافذ.
3) حدّد عدد الطبقات.
4) استخدم حاسبة الدهان.

## FAQ
س: كم تغطي علبة 20 لتر؟  
ج: يختلف حسب النوع والخشونة، غالبًا 100-140 متر للطبقة الواحدة.

## CTA
جرّب حاسبة الكميات داخل AmmarJo الآن.
'''
  },
  {
    'slug': 'request-technician-fast',
    'title': 'كيف تطلب فني موثوق بسرعة في الأردن',
    'content': '''
## لماذا تتأخر أعمال الصيانة؟
لأن الطلب غالبًا يفتقد التفاصيل والصور.

## طريقة الطلب الذكي
1) ارفع صورة واضحة.
2) اكتب وصف المشكلة.
3) حدد المدينة والوقت المتاح.
4) قارن التقييمات والسعر.

## FAQ
س: كيف أتأكد من جودة الفني؟  
ج: راجع التقييمات وسجل الأعمال.

## CTA
قدّم طلب فني الآن واستلم عروضًا خلال وقت قصير.
'''
  },
  {
    'slug': 'reverse-tender-benefits',
    'title': 'المناقصة العكسية: كيف تحصل على أفضل سعر للمواد؟',
    'content': '''
## الفكرة
بدل البحث عن متجر، ارفع طلبك ودع المتاجر تتنافس على السعر.

## خطوات التنفيذ
1) ارفع صورة المنتج المطلوب.
2) اختر التصنيف.
3) انتظر العروض.
4) اختر الأنسب وأضفه للسلة.

## FAQ
س: هل أرى اسم المتجر قبل القبول؟  
ج: لا، لضمان حيادية العرض.

## CTA
افتح صفحة "اطلب تسعيرة بالصورة" وابدأ الآن.
'''
  },
  {
    'slug': 'used-market-safe-buying',
    'title': 'دليل الشراء الآمن من سوق المستعمل',
    'content': '''
## قبل الشراء
افحص الصور، السعر، والوصف.

## أثناء المعاينة
1) افحص الحالة الفعلية.
2) جرّب المنتج إن أمكن.
3) طابق المواصفات مع الإعلان.

## FAQ
س: كيف أتجنب الاحتيال؟  
ج: لا تدفع كامل المبلغ قبل الفحص.

## CTA
تصفح سوق المستعمل في AmmarJo بفلترة دقيقة.
'''
  },
  {
    'slug': 'wholesale-directory-guide',
    'title': 'كيف تستفيد من دليل تجار الجملة لزيادة هامش الربح',
    'content': '''
## لماذا الجملة مهمة؟
الشراء بالجملة يقلل تكلفة الوحدة ويرفع هامش الربح.

## خطة شراء
1) صنف المنتجات سريعة الدوران.
2) اطلب عينات.
3) فاوض على سعر الكمية.

## FAQ
س: ما أقل كمية مناسبة؟  
ج: ابدأ بكمية تجريبية ثم توسع تدريجيًا.

## CTA
ادخل دليل تجار الجملة الآن.
'''
  },
  {
    'slug': 'plumbing-leak-fixes',
    'title': 'حل تسربات المياه المنزلية: خطوات سريعة قبل حضور الفني',
    'content': '''
## أول 10 دقائق مهمة
1) اغلق مصدر المياه.
2) حدد مكان التسرب.
3) وثّق بالصور.

## حلول مؤقتة
استخدم شريط مانع التسرب أو وصلة مؤقتة لحين وصول الفني.

## FAQ
س: متى أحتاج فني فورًا؟  
ج: عند التسرب القوي أو قرب الكهرباء.

## CTA
اطلب فني سباكة عبر AmmarJo.
'''
  },
  {
    'slug': 'electric-safety-home',
    'title': 'السلامة الكهربائية في المنزل: أخطاء شائعة يجب تجنبها',
    'content': '''
## أخطاء شائعة
- تحميل زائد على مشترك واحد.
- تمديدات عشوائية.
- إهمال القواطع.

## الوقاية
1) افحص اللوحة كل 6 أشهر.
2) استخدم أدوات أصلية.
3) استعن بفني معتمد.

## FAQ
س: هل القاطع يفصل بلا سبب؟  
ج: غالبًا يوجد حمل زائد أو تماس.

## CTA
احجز فحص كهربائي سريع الآن.
'''
  },
  {
    'slug': 'construction-budgeting',
    'title': 'إدارة ميزانية البناء من الصفر حتى التسليم',
    'content': '''
## قاعدة ذهبية
قسّم الميزانية إلى مراحل: هيكل، تشطيب، طوارئ.

## خطوات
1) ضع سقفًا لكل مرحلة.
2) راقب الصرف أسبوعيًا.
3) احتفظ بنسبة طوارئ 10%.

## FAQ
س: ما أكبر سبب لتجاوز الميزانية؟  
ج: تغييرات متأخرة أثناء التنفيذ.

## CTA
ابدأ تخطيطك عبر أدوات AmmarJo.
'''
  },
  {
    'slug': 'before-after-maintenance',
    'title': 'قبل/بعد الصيانة: كيف تقيس جودة التنفيذ فعليًا؟',
    'content': '''
## لماذا التوثيق مهم؟
لضمان استلام الشغل بالمواصفات.

## قائمة فحص
1) صور قبل وبعد.
2) اختبار تشغيل.
3) ملاحظات مكتوبة.
4) طلب ضمان إن توفر.

## FAQ
س: ماذا أفعل إذا لم تطابق النتيجة الاتفاق؟  
ج: افتح بلاغ متابعة داخل المنصة.

## CTA
تابع طلباتك وتقييم التنفيذ من حسابك.
'''
  },
];

final List<SocialScript> tenViralScripts = tenReadyArticles
    .map(
      (a) => SocialScript(
        articleSlug: a['slug']!,
        tiktok: 'Hook: "الغالبية تخسر فلوس هنا!"\nBody: 3 خطوات سريعة من المقال.\nCTA: اقرأ الدليل الكامل في المدونة.',
        facebook: 'مشكلة شائعة + حل عملي + رابط المقال + سؤال للنقاش.',
        instagram: 'نصيحة اليوم من AmmarJo ✨\n- نقطة 1\n- نقطة 2\n- نقطة 3\n#مواد_بناء #الأردن',
      ),
    )
    .toList();

final List<DailyPlanItem> plan30Days = List<DailyPlanItem>.generate(
  30,
  (i) => DailyPlanItem(
    day: i + 1,
    blogTopic: tenReadyArticles[i % tenReadyArticles.length]['title']!,
    videoIdea: 'فيديو قصير: ${tenReadyArticles[i % tenReadyArticles.length]['title']}',
    platform: i % 3 == 0 ? 'TikTok' : (i % 3 == 1 ? 'Facebook' : 'Instagram'),
    goal: i % 2 == 0 ? 'Traffic' : 'Leads',
  ),
);

final List<VideoIdea> daily30VideoIdeas = List<VideoIdea>.generate(
  30,
  (i) => VideoIdea(
    day: i + 1,
    hook: 'خطأ رقم ${i + 1} يسبب خسارة في مشروعك!',
    topic: tenReadyArticles[i % tenReadyArticles.length]['title']!,
    outline: 'مشكلة سريعة > مثال واقعي > 3 حلول > نتيجة قبل/بعد',
    cta: 'ادخل المقال الكامل في مدونة AmmarJo واحجز الخدمة المناسبة.',
  ),
);

