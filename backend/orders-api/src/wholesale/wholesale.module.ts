import { Module } from '@nestjs/common';
import { EventsCoreModule } from '../events/events-core.module';
import { StoresModule } from '../stores/stores.module';
import { CategoryService } from './category.service';
import { CatalogReadController } from './catalog-read.controller';
import { ProductService } from './product.service';
import { StoreService } from './store.service';
import { WholesaleController } from './wholesale.controller';
import { WholesaleService } from './wholesale.service';

@Module({
  imports: [EventsCoreModule, StoresModule],
  controllers: [WholesaleController, CatalogReadController],
  providers: [WholesaleService, StoreService, CategoryService, ProductService],
  exports: [WholesaleService, StoreService, CategoryService, ProductService],
})
export class WholesaleModule {}
