import { Module } from '@nestjs/common';
import { AlgoliaProductsService } from './algolia-products.service';
import { CatalogPgService } from './catalog-pg.service';
import { InternalApiKeyGuard } from './internal-api-key.guard';
import { ProductSearchSyncService } from './product-search-sync.service';
import { SearchController } from './search.controller';
import { SearchInternalController } from './search-internal.controller';

@Module({
  controllers: [SearchController, SearchInternalController],
  providers: [
    CatalogPgService,
    AlgoliaProductsService,
    ProductSearchSyncService,
    InternalApiKeyGuard,
  ],
  exports: [CatalogPgService, AlgoliaProductsService, ProductSearchSyncService, InternalApiKeyGuard],
})
export class SearchModule {}
