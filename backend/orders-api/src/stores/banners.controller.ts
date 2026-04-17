import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';

@Controller('banners')
@UseGuards(TenantContextGuard, ApiPolicyGuard)
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 300 } })
export class BannersController {
  @Get()
  list() {
    return {
      items: [
        {
          id: '1',
          imageUrl: 'https://picsum.photos/seed/ammarjo-banner/600/200',
          title: 'عرض خاص',
        },
      ],
    };
  }
}
