import { Module } from '@nestjs/common';
import { HomeModule } from '../home/home.module';
import { AlgoliaSyncService } from '../search/algolia-sync.service';
import { CategoriesController, CategoriesMutateController } from './categories.controller';
import { CategoriesService } from './categories.service';
import { ProductVariantsController } from './product-variants.controller';
import { ProductVariantsService } from './product-variants.service';
import { ProductsController, ProductsFilterPublicController, ProductsMutateController } from './products.controller';
import { BannersController } from './banners.controller';
import { ProductsService } from './products.service';
import { StoreCommissionsController } from './store-commissions.controller';
import { StoreCommissionsService } from './store-commissions.service';
import { StoreOffersController, StoreOffersMutateController } from './store-offers.controller';
import { StoreOffersService } from './store-offers.service';
import { StoresController, StoresPublicController } from './stores.controller';
import { StoresService } from './stores.service';
import { StoreRequestsController } from './store-requests.controller';
import { StoreRequestsService } from './store-requests.service';

@Module({
  imports: [HomeModule],
  controllers: [
    // IMPORTANT: StoresPublicController MUST be registered before StoresController
    // so that public routes like GET /stores/store-types are not shadowed by the
    // authenticated GET /stores/:id route.
    StoresPublicController,
    StoresController,
    StoreRequestsController,
    CategoriesController,
    CategoriesMutateController,
    ProductsController,
    ProductsMutateController,
    ProductsFilterPublicController,
    ProductVariantsController,
    StoreOffersController,
    StoreOffersMutateController,
    StoreCommissionsController,
    BannersController,
  ],
  providers: [
    StoresService,
    CategoriesService,
    ProductsService,
    ProductVariantsService,
    StoreOffersService,
    StoreCommissionsService,
    StoreRequestsService,
    AlgoliaSyncService,
  ],
  exports: [
    StoresService,
    CategoriesService,
    ProductsService,
    ProductVariantsService,
    StoreCommissionsService,
    AlgoliaSyncService,
  ],
})
export class StoresModule {}
