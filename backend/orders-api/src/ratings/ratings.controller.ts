import { Body, Controller, Get, Logger, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { CreateReviewDto, type RatingTargetType } from './ratings.types';
import { RatingsService } from './ratings.service';

@Controller('ratings')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class RatingsController {
  private readonly logger = new Logger(RatingsController.name);

  constructor(private readonly ratings: RatingsService) {}

  @Post()
  @RequirePermissions('orders.write')
  create(@Body() body: CreateReviewDto) {
    return this.ratings.createReview(body);
  }

  @Get(':targetType/:targetId')
  @RequirePermissions('orders.read')
  async listByTarget(
    @Param('targetType') targetType: RatingTargetType,
    @Param('targetId') targetId: string,
  ) {
    try {
      return await this.ratings.getReviewsByTarget(targetType, targetId);
    } catch (error) {
      this.logger.warn(
        `ratings list failed for ${targetType}/${targetId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return [];
    }
  }

  @Get(':targetType/:targetId/aggregate')
  @RequirePermissions('orders.read')
  aggregate(@Param('targetType') targetType: RatingTargetType, @Param('targetId') targetId: string) {
    return this.ratings.getAggregate(targetType, targetId);
  }
}

