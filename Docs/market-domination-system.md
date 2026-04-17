# Market Domination System (Jordan)

## 1) Code Structure

- `lib/web_pages/blog_page.dart`
  - Blog listing with:
    - categories
    - tags
    - search
    - SEO slug navigation (`/blog/{slug}`)
  - Blog detail with related posts
- `lib/web_pages/blog_growth_engine.dart`
  - `jordan200Keywords` (200 keyword plans: keyword + intent + article title)
  - `tenReadyArticles` (10 full Arabic articles with FAQ + CTA)
  - `tenViralScripts` (TikTok + Facebook + Instagram)
  - `plan30Days` (daily execution 30-day plan)
  - `daily30VideoIdeas` (30 short-form video concepts)

## 2) DB Schema (Execution Ready)

Recommended Firestore schema:

- `blog_posts/{postId}`
  - `slug` (unique)
  - `title`
  - `excerpt`
  - `content`
  - `categoryId`
  - `tagIds` (array)
  - `authorId`
  - `seoTitle`
  - `seoDescription`
  - `publishedAt`
  - `updatedAt`
  - `status` (`draft|published`)
  - `legacyPaths` (array for migration)
- `blog_categories/{categoryId}`
  - `name`
  - `slug`
- `blog_tags/{tagId}`
  - `name`
  - `slug`
- `blog_authors/{authorId}`
  - `name`
  - `bio`
  - `avatarUrl`
- `blog_redirects/{id}`
  - `fromPath`
  - `toPath`
  - `statusCode` (301)

## 3) Migration Plan (Zero Ranking Loss)

1. Export old blog URLs + metadata.
2. Map each old URL to new slug.
3. Store redirects in `blog_redirects`.
4. Keep old titles/H1 and improve content (do not fully rewrite weak pages at once).
5. Keep publish dates where possible.
6. Generate canonical URLs and ensure no duplicates.
7. Validate 301 chain (no 302/404 leakage).
8. Submit updated sitemap.

## 4) Tech SEO Checklist

- FAQ schema + HowTo schema for guide pages.
- OpenGraph + Twitter cards.
- Fast loading:
  - image compression + cache
  - lazy sections
- Mobile-first + RTL.
- Clean slugs in Arabic/Latin (stable format).

## 5) AI Content Engine

- AI article template:
  - Problem
  - Steps
  - FAQ
  - CTA
- Auto internal linking rules:
  - link to service page + calculator + related article
- AI short summaries for social and SERP snippets.

## 6) Local SEO Pages

Create landing pages for:

- Amman
- Irbid
- Zarqa
- Aqaba
- Salt
- Madaba

Template:
- local problem
- local price ranges
- trusted solution path
- CTA (WhatsApp + service request)

## 7) Conversion System

- CTA blocks in every article:
  - "اطلب عرض سعر"
  - "احجز فني"
  - "جرّب حاسبة الكميات"
- Sticky WhatsApp button on web.
- Lead capture form:
  - name
  - phone
  - city
  - need type

## 8) Viral Distribution

Flow:

1. Publish blog
2. Extract 1-2 reels
3. Publish on TikTok + IG + FB
4. Push to FB groups
5. Retarget with ads on top posts

## 9) Marketing Plan

- SEO: long-tail + local + problem-solving intent.
- TikTok growth: daily hooks + before/after content.
- Facebook groups: value posts + link only when relevant.
- Paid ads: retarget blog visitors.
- Influencers: micro-creators in DIY/construction niche.

## 10) Tracking + Improvement Loop

Track weekly:

- CTR
- ranking movement
- scroll depth
- lead conversion rate
- watch time (video)

Auto actions:

- CTR low → rewrite titles/meta.
- Rank 5-15 → add internal links + FAQ block.
- Bounce high → improve intro/hook + visual blocks.
- Leads low → test CTA copy and placement.

