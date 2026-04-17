import { Module } from '@nestjs/common';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { AiStoreBuilderService } from './ai-store-builder.service';
import { DevOrInternalApiKeyGuard } from './dev-or-internal-api-key.guard';
import { StoreBuilderDevController } from './store-builder-dev.controller';
import { StoreBuilderController } from './store-builder.controller';
import { StoreBuilderService } from './store-builder.service';
import { StoreDomainDevSeedService } from './store-domain-dev-seed.service';

@Module({
  controllers: [StoreBuilderController, StoreBuilderDevController],
  providers: [
    StoreBuilderService,
    AiStoreBuilderService,
    StoreDomainDevSeedService,
    InternalApiKeyGuard,
    DevOrInternalApiKeyGuard,
  ],
  exports: [StoreBuilderService],
})
export class StoreBuilderModule {}

