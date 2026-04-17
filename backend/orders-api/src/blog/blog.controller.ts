import { Controller, Get, Query } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';

/** Public blog listing for the marketing site (`GET /blog`). */
@Controller('blog')
@ApiPolicy({ auth: false, tenant: 'none', rateLimit: { rpm: 90 } })
export class BlogController {
  @Get()
  list(@Query('includeBanners') includeBanners?: string) {
    const items = [
      {
        id: '1',
        slug: 'construction-materials-guide',
        title: 'دليل مواد البناء',
        excerpt: 'نظرة عامة على اختيار المواد المناسبة لمشروعك.',
        content: 'محتوى المقال الكامل يمكن استبداله من لوحة الإدارة لاحقاً.',
        category: 'مواد البناء',
        tags: ['الأردن', 'AmmarJo', 'نصائح'],
        author: 'فريق AmmarJo',
        publishedAt: new Date().toISOString(),
        seoTitle: 'دليل مواد البناء | AmmarJo',
        seoDescription: 'نصائح لاختيار مواد البناء.',
      },
    ];
    const out: Record<string, unknown> = { items };
    if (includeBanners === 'true') {
      out['banners'] = [];
    }
    return out;
  }
}
