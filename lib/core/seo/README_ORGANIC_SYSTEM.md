Organic Traffic System (No UI Impact)
====================================

This project includes a background-only organic SEO growth layer for Flutter Web.

Collections used:
- `seo_keywords`: keyword strategy objects per page target
- `seo_content_profiles`: blog SEO structure/length/FAQ suggestions
- `seo_internal_links`: dynamic similarity-based related links graph
- `seo_indexing_queue`: indexing refresh tasks for new/updated content
- `seo_sitemap_signals`: latest sitemap refresh signal
- `seo_page_metrics`: route-level impression/click aggregates
- `seo_traffic_actions`: suggested actions for underperforming pages

Startup hooks:
- `SeoIndexingHooks.start()`
- `OrganicTrafficSystem.instance.start()`

No widget/layout/design changes are required; all logic runs in the background.
