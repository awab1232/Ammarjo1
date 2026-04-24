import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../core/config/backend_orders_config.dart';
import '../core/contracts/feature_state.dart';
import '../core/seo/seo_routes.dart';
import '../core/seo/seo_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/web_image_url.dart';
import '../core/widgets/ammar_cached_image.dart';
import 'blog_growth_engine.dart';

class BlogPost {
  const BlogPost({
    required this.id,
    required this.slug,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.category,
    required this.tags,
    required this.author,
    required this.publishedAt,
    required this.seoTitle,
    required this.seoDescription,
  });

  final String id;
  final String slug;
  final String title;
  final String excerpt;
  final String content;
  final String category;
  final List<String> tags;
  final String author;
  final DateTime publishedAt;
  final String seoTitle;
  final String seoDescription;
}

class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedCategory;
  String? _selectedTag;

  List<BlogPost> get _posts => _seedBlogPosts;

  List<String> get _categories =>
      _posts.map((e) => e.category).toSet().toList()..sort();
  List<String> get _tags =>
      _posts.expand((e) => e.tags).toSet().toList()..sort();

  List<BlogPost> get _filtered {
    final query = _searchCtrl.text.trim();
    return _posts.where((p) {
      final byCategory =
          _selectedCategory == null || p.category == _selectedCategory;
      final byTag = _selectedTag == null || p.tags.contains(_selectedTag);
      final bySearch =
          query.isEmpty ||
          p.title.contains(query) ||
          p.excerpt.contains(query) ||
          p.tags.any((t) => t.contains(query));
      return byCategory && byTag && bySearch;
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SeoService.apply(
      const SeoData(
        title: 'AmmarJo Blog',
        description:
            'Construction insights, maintenance guides, and marketplace updates from AmmarJo.',
        keywords: 'AmmarJo blog, construction tips, maintenance guides',
        path: '/blog',
        structuredData: <Map<String, dynamic>>[
          <String, dynamic>{
            '@context': 'https://schema.org',
            '@type': 'CollectionPage',
            'name': 'AmmarJo Blog',
            'description':
                'Construction insights, maintenance guides, and marketplace updates from AmmarJo.',
          },
        ],
      ),
      updatePath: true,
    );
    return FutureBuilder<FeatureState<List<BlogPost>>>(
      future: _fetchBlogPosts(),
      builder: (context, snap) {
        final remote = switch (snap.data) {
          FeatureSuccess(:final data) => data,
          _ => <BlogPost>[],
        };
        final posts = remote.isNotEmpty ? _applyFilter(remote) : _filtered;
        return Scaffold(
          appBar: AppBar(
            title: const Text('مدونة AmmarJo'),
            backgroundColor: AppColors.primaryOrange,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              if (kIsWeb) const _WebDownloadPromoInline(),
              const _BlogAdBanners(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث في المقالات...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        decoration: const InputDecoration(labelText: 'التصنيف'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('الكل'),
                          ),
                          ..._categories.map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedCategory = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedTag,
                        decoration: const InputDecoration(labelText: 'الوسم'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('الكل'),
                          ),
                          ..._tags.map(
                            (t) => DropdownMenuItem<String>(
                              value: t,
                              child: Text(t),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedTag = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: posts.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد نتائج',
                          style: GoogleFonts.tajawal(),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: posts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = posts[i];
                          return Card(
                            child: ListTile(
                              title: Text(
                                p.title,
                                style: GoogleFonts.tajawal(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${p.category} • ${p.author}',
                                style: GoogleFonts.tajawal(),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 18,
                              ),
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/blog/${p.slug}',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<BlogPost> _applyFilter(List<BlogPost> input) {
    final query = _searchCtrl.text.trim();
    return input.where((p) {
      final byCategory =
          _selectedCategory == null || p.category == _selectedCategory;
      final byTag = _selectedTag == null || p.tags.contains(_selectedTag);
      final bySearch =
          query.isEmpty ||
          p.title.contains(query) ||
          p.excerpt.contains(query) ||
          p.tags.any((t) => t.contains(query));
      return byCategory && byTag && bySearch;
    }).toList();
  }

  Future<FeatureState<List<BlogPost>>> _fetchBlogPosts() async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL is missing for blog posts.');
    http.Response res;
    try {
      res = await http.get(Uri.parse('$base/blog')).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return FeatureState.failure('TIMEOUT');
    } on Object {
      return FeatureState.failure('UNEXPECTED_ERROR');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('Failed to load blog posts (${res.statusCode}).');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on Object {
      return FeatureState.failure('INVALID_JSON');
    }
    final items = decoded is Map && decoded['items'] is List ? decoded['items'] as List : const <dynamic>[];
    return FeatureState.success(
      items.whereType<Map>().map((e) => _postFromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }

  BlogPost _postFromMap(Map<String, dynamic> d) {
    final tagsRaw = d['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).toList()
        : const <String>[];
    return BlogPost(
      id: d['id']?.toString() ?? '',
      slug: d['slug']?.toString() ??
          (d['id']?.toString() ?? ''),
      title: d['title']?.toString() ?? 'مقال',
      excerpt: d['excerpt']?.toString() ?? '',
      content: d['content']?.toString() ?? '',
      category: d['category']?.toString() ?? 'عام',
      tags: tags,
      author: d['author']?.toString() ?? 'فريق AmmarJo',
      publishedAt: DateTime.tryParse(
            d['publishedAt']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      seoTitle:
          d['seoTitle']?.toString() ?? (d['title']?.toString() ?? 'AmmarJo'),
      seoDescription: d['seoDescription']?.toString() ?? '',
    );
  }
}

class BlogDetailPage extends StatelessWidget {
  const BlogDetailPage({super.key, required this.articleId});
  final String articleId;

  @override
  Widget build(BuildContext context) {
    final post = _seedBlogPosts.cast<BlogPost?>().firstWhere(
      (p) => p!.id == articleId || p.slug == articleId,
      orElse: () => null,
    );
    if (post == null) {
      SeoService.apply(
        const SeoData(
          title: 'Blog | AmmarJo',
          description: 'Browse AmmarJo blog content.',
          path: '/blog',
        ),
      );
      return Scaffold(
        appBar: AppBar(title: const Text('المقال غير موجود')),
        body: const Center(child: Text('لم يتم العثور على المقال')),
      );
    }
    final related = _seedBlogPosts
        .where(
          (e) =>
              e.id != post.id &&
              (e.category == post.category || e.tags.any(post.tags.contains)),
        )
        .take(3)
        .toList();
    SeoService.apply(
      SeoData(
        title: post.seoTitle.trim().isEmpty
            ? '${post.title} | AmmarJo'
            : post.seoTitle,
        description: post.seoDescription.trim().isEmpty
            ? post.excerpt
            : post.seoDescription,
        keywords: 'AmmarJo, blog, ${post.category}, ${post.tags.join(", ")}',
        path: SeoRoutes.blog(post.slug),
        lastModified: post.publishedAt,
        structuredData: <Map<String, dynamic>>[
          <String, dynamic>{
            '@context': 'https://schema.org',
            '@type': 'Article',
            'headline': post.title,
            'description': post.excerpt,
            'author': <String, dynamic>{'@type': 'Person', 'name': post.author},
            'datePublished': post.publishedAt.toUtc().toIso8601String(),
          },
        ],
        internalLinks: related.map((r) => SeoRoutes.blog(r.slug)).toList(),
      ),
      updatePath: true,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(post.title),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (kIsWeb) const _WebDownloadPromoInline(),
          const _BlogAdBanners(),
          const SizedBox(height: 12),
          Text(
            post.title,
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${post.author} • ${post.category}',
            style: GoogleFonts.tajawal(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
          Text(
            post.content,
            style: GoogleFonts.tajawal(height: 1.8, fontSize: 16),
          ),
          const SizedBox(height: 22),
          Text(
            'مقالات ذات صلة',
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          ...related.map(
            (r) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                r.title,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(r.category, style: GoogleFonts.tajawal()),
              onTap: () =>
                  Navigator.pushReplacementNamed(context, '/blog/${r.slug}'),
            ),
          ),
        ],
      ),
    );
  }
}

final List<BlogPost> _seedBlogPosts = List<BlogPost>.generate(
  tenReadyArticles.length,
  (i) {
    final a = tenReadyArticles[i];
    return BlogPost(
      id: '${i + 1}',
      slug: a['slug']!,
      title: a['title']!,
      excerpt: a['content']!
          .split('\n')
          .where((e) => e.trim().isNotEmpty)
          .take(2)
          .join(' '),
      content: a['content']!,
      category: i < 3
          ? 'مواد البناء'
          : i < 6
          ? 'الصيانة'
          : 'إدارة المشاريع',
      tags: <String>['الأردن', 'AmmarJo', if (i.isEven) 'نصائح' else 'حلول'],
      author: 'فريق AmmarJo',
      publishedAt: DateTime(2026, 4, i + 1),
      seoTitle: '${a['title']} | AmmarJo',
      seoDescription: a['title']!,
    );
  },
);

class _BlogAdBanners extends StatelessWidget {
  const _BlogAdBanners();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
      future: _fetchBanners(),
      builder: (context, snap) {
        final docs = switch (snap.data) {
          FeatureSuccess(:final data) => data,
          _ => <Map<String, dynamic>>[],
        };
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          children: docs.map((d) => _BlogBannerCard(data: d)).toList(),
        );
      },
    );
  }

  Future<FeatureState<List<Map<String, dynamic>>>> _fetchBanners() async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL is missing for blog banners.');
    http.Response res;
    try {
      res = await http.get(Uri.parse('$base/blog?includeBanners=true')).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return FeatureState.failure('TIMEOUT');
    } on Object {
      return FeatureState.failure('UNEXPECTED_ERROR');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('Failed to load blog banners (${res.statusCode}).');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on Object {
      return FeatureState.failure('INVALID_JSON');
    }
    final items = decoded is Map && decoded['banners'] is List ? decoded['banners'] as List : const <dynamic>[];
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }
}

class _BlogBannerCard extends StatelessWidget {
  const _BlogBannerCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        webSafeImageUrl(data['imageUrl']?.toString() ?? '');
    final title = data['title']?.toString() ?? 'إعلان';
    final links = <String>[
      data['link1']?.toString() ?? '',
      data['link2']?.toString() ?? '',
      data['link3']?.toString() ?? '',
    ].where((e) => e.trim().isNotEmpty).toList();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: SizedBox(
                height: 150,
                child: AmmarCachedImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  productTileStyle: true,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: links
                      .map(
                        (link) => FilledButton.tonal(
                          onPressed: () => _openLink(link),
                          child: Text(
                            'رابط إعلان',
                            style: GoogleFonts.tajawal(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

class _WebDownloadPromoInline extends StatelessWidget {
  const _WebDownloadPromoInline();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFFF8A3D)],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.rocket_launch_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'اقرأ المقال ثم كمّل من التطبيق: إشعارات فورية + متابعة الطلبات + عروض خاصة',
              style: GoogleFonts.tajawal(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => launchUrl(
              Uri.parse('https://play.google.com/store'),
              mode: LaunchMode.platformDefault,
            ),
            child: Text(
              'حمّل الآن',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
