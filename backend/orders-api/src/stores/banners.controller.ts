import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { HomeService } from '../home/home.service';
import { TenantContextGuard } from '../identity/tenant-context.guard';

@Controller('banners')
@UseGuards(TenantContextGuard, ApiPolicyGuard)
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 300 } })
export class BannersController {
  constructor(private readonly home: HomeService) {}

  /** Banner slides from `home_cms.slider` (same source as `GET /home/cms` primarySlider). */
  @Get()
  list() {
    return this.home.getBannersArray();
  }
}
