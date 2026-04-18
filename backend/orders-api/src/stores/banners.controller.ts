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

  /** Legacy list shape; items come from `home_cms.slider` (see `GET /home/cms`). */
  @Get()
  list() {
    return this.home.getBannersList();
  }
}
