import { Controller, Logger, Post, Query, UseGuards } from '@nestjs/common';
import { DevOrInternalApiKeyGuard } from './dev-or-internal-api-key.guard';
import { StoreBuilderService } from './store-builder.service';
import {
  DEV_SEED_HYBRID_STORE_ID,
  DEV_SEED_OWNER_ID,
  StoreDomainDevSeedService,
} from './store-domain-dev-seed.service';

@Controller('internal/dev')
@UseGuards(DevOrInternalApiKeyGuard)
export class StoreBuilderDevController {
  private readonly logger = new Logger(StoreBuilderDevController.name);

  constructor(
    private readonly storeBuilder: StoreBuilderService,
    private readonly domainSeed: StoreDomainDevSeedService,
  ) {}

  /**
   * Creates hybrid builder data for store_demo_1 via AI bootstrap, then optionally mirrors categories/products into domain tables.
   * Non-production: open. Production: requires `x-internal-api-key` (same as other internal routes).
   */
  @Post('seed-initial-store')
  async seedInitialStore(@Query('products') products?: string) {
    const seedProducts = products !== 'false' && products !== '0';

    const builder = await this.storeBuilder.bootstrapForDevSeed(
      {
        storeId: DEV_SEED_HYBRID_STORE_ID,
        ownerId: DEV_SEED_OWNER_ID,
        storeType: 'construction_store',
      },
      DEV_SEED_OWNER_ID,
    );

    const categoryCount = builder.categories?.length ?? 0;
    let productCount = 0;

    const r = await this.domainSeed.seedDomainFromHybrid(DEV_SEED_HYBRID_STORE_ID, {
      includeProducts: seedProducts,
    });
    productCount = r.productCount;

    this.logger.log(
      JSON.stringify({
        kind: 'dev_seed_store_created',
        storeId: DEV_SEED_HYBRID_STORE_ID,
        categoryCount,
        productCount,
      }),
    );

    return {
      ok: true,
      storeId: DEV_SEED_HYBRID_STORE_ID,
      domainStoreUuid: this.domainSeed.domainStoreUuid(),
      categoryCount,
      productCount,
      seedProducts,
      builder,
    };
  }
}
