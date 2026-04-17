import { Injectable } from '@nestjs/common';
import type { StoreBuilderStoreType } from './store-builder.types';

type SeedCategory = {
  name: string;
  imageUrl: string;
  sortOrder: number;
  children: Array<{ name: string; imageUrl: string; sortOrder: number }>;
};

@Injectable()
export class AiStoreBuilderService {
  private categorySeeds(storeType: StoreBuilderStoreType): SeedCategory[] {
    if (storeType === 'home_store') {
      return [
        {
          name: 'Top Home Essentials',
          imageUrl: '',
          sortOrder: 1,
          children: [
            { name: 'Smart Appliances', imageUrl: '', sortOrder: 1 },
            { name: 'Kitchen Must-Haves', imageUrl: '', sortOrder: 2 },
          ],
        },
        {
          name: 'Comfort Upgrades',
          imageUrl: '',
          sortOrder: 2,
          children: [
            { name: 'Cooling & Heating', imageUrl: '', sortOrder: 1 },
            { name: 'Home Care Tools', imageUrl: '', sortOrder: 2 },
          ],
        },
      ];
    }
    if (storeType === 'wholesale_store') {
      return [
        {
          name: 'Fast Moving Bulk Lines',
          imageUrl: '',
          sortOrder: 1,
          children: [
            { name: 'Top Seller Packs', imageUrl: '', sortOrder: 1 },
            { name: 'Contractor Favorites', imageUrl: '', sortOrder: 2 },
          ],
        },
        {
          name: 'Margin Booster Products',
          imageUrl: '',
          sortOrder: 2,
          children: [
            { name: 'Promo Bundles', imageUrl: '', sortOrder: 1 },
            { name: 'Seasonal Demand', imageUrl: '', sortOrder: 2 },
          ],
        },
      ];
    }
    return [
      {
        name: 'High Demand Building Supplies',
        imageUrl: '',
        sortOrder: 1,
        children: [
          { name: 'Cement & Concrete', imageUrl: '', sortOrder: 1 },
          { name: 'Blocks & Bricks', imageUrl: '', sortOrder: 2 },
        ],
      },
      {
        name: 'Finish & Decor Bestsellers',
        imageUrl: '',
        sortOrder: 2,
        children: [
          { name: 'Paint & Coatings', imageUrl: '', sortOrder: 1 },
          { name: 'Flooring & Tiles', imageUrl: '', sortOrder: 2 },
        ],
      },
      {
        name: 'Plumbing & Electrical Picks',
        imageUrl: '',
        sortOrder: 3,
        children: [
          { name: 'Pipes & Fittings', imageUrl: '', sortOrder: 1 },
          { name: 'Switches & Wires', imageUrl: '', sortOrder: 2 },
        ],
      },
    ];
  }

  buildInitialStructure(storeType: StoreBuilderStoreType): {
    categories: SeedCategory[];
    layoutSections: Array<{ sectionType: string; sortOrder: number; configJson: Record<string, unknown> }>;
  } {
    return {
      categories: this.categorySeeds(storeType),
      layoutSections: [
        { sectionType: 'featured_products', sortOrder: 1, configJson: { maxItems: 12, source: 'top_conversion' } },
        { sectionType: 'new_arrivals', sortOrder: 2, configJson: { maxItems: 12, source: 'latest' } },
        { sectionType: 'offers', sortOrder: 3, configJson: { maxItems: 12, source: 'best_discount' } },
        { sectionType: 'category_previews', sortOrder: 4, configJson: { productsPerCategory: 3 } },
      ],
    };
  }

  buildSuggestions(storeType: StoreBuilderStoreType): {
    recommendedCategories: string[];
    recommendedRenames: Array<{ from: string; to: string }>;
    suggestedFeaturedProducts: string[];
    layoutImprovements: string[];
  } {
    const storeLabel =
      storeType === 'home_store'
        ? 'home appliances'
        : storeType === 'wholesale_store'
          ? 'bulk wholesale'
          : 'construction';
    return {
      recommendedCategories: [
        `Top ${storeLabel} deals`,
        'Bundles with high repeat purchase',
        'Quick delivery picks',
      ],
      recommendedRenames: [
        { from: 'General', to: 'Best Value Picks' },
        { from: 'Other', to: 'Staff Recommended' },
      ],
      suggestedFeaturedProducts: ['Top margin product', 'Best seller product', 'New high-demand product'],
      layoutImprovements: [
        'Move high-conversion category to first position',
        'Add promotional strip above featured products',
        'Use category preview section with 3 products each',
      ],
    };
  }
}

