import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { HomeService } from './home.service';

@Controller('home')
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 120 } })
export class HomeController {
  constructor(private readonly homeService: HomeService) {}

  @Get('/sections')
  async getHomeSections(@Query('storeTypeId') storeTypeId?: string) {
    return this.homeService.getSections(storeTypeId);
  }

  /** Slider (3 slides), offers strip, bottom banner — editable via admin `home-cms`. */
  @Get('/cms')
  getCms() {
    return this.homeService.getPublicCms();
  }

  @Get('/home-sections/:id/sub-categories')
  async getSubCategoriesBySection(@Param('id') id: string) {
    return this.homeService.getSubCategories(id);
  }
}
