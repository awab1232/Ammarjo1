import { BadRequestException, Body, Controller, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { DriverStatusDto, ManualAssignDriverDto, OrderIdBodyDto, RegisterDriverDto } from './dto/driver-requests.dto';
import { DriversService } from './drivers.service';

@Controller()
export class DriversController {
  constructor(private readonly drivers: DriversService) {}

  @Get('drivers/available')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async listAvailableDrivers() {
    const drivers = await this.drivers.listAvailableDrivers();
    return { drivers };
  }

  @Get('drivers/workbench')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('orders.write')
  async workbench(@Req() req: RequestWithFirebase) {
    return this.drivers.getWorkbench(req.firebaseUid!);
  }

  @Post('drivers/register')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 30 } })
  @RequirePermissions('orders.write')
  async register(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(RegisterDriverDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.registerDriver(req.firebaseUid!, dto.name, dto.phone);
  }

  @Post('drivers/location')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 600 } })
  @RequirePermissions('orders.write')
  async location(@Req() req: RequestWithFirebase, @Body() raw: Record<string, unknown>) {
    const lat = Number(raw?.lat ?? raw?.latitude);
    const lng = Number(raw?.lng ?? raw?.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      throw new BadRequestException('lat and lng are required');
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw new BadRequestException('coordinates out of range');
    }
    return this.drivers.updateLocation(req.firebaseUid!, lat, lng);
  }

  @Post('drivers/status')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async status(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(DriverStatusDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.updateDriverStatus(req.firebaseUid!, dto.status);
  }

  @Post('drivers/accept-order')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async accept(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(OrderIdBodyDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.acceptOrder(req.firebaseUid!, dto.orderId);
  }

  @Post('drivers/reject-order')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async reject(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(OrderIdBodyDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.rejectOrder(req.firebaseUid!, dto.orderId);
  }

  @Post('drivers/auto-assign')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 30 } })
  @RequirePermissions('orders.write')
  async autoAssign(@Body() raw: unknown) {
    const dto = plainToInstance(OrderIdBodyDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.autoAssignDriver(dto.orderId);
  }

  @Post('drivers/on-the-way')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async onTheWay(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(OrderIdBodyDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.markOnTheWay(req.firebaseUid!, dto.orderId);
  }

  @Post('drivers/complete-order')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async complete(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(OrderIdBodyDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.completeOrder(req.firebaseUid!, dto.orderId);
  }

  @Patch('orders/:id/assign-driver')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 30 } })
  @RequirePermissions('orders.write')
  async manualAssign(
    @Param('id') orderId: string,
    @Body() raw: unknown,
  ) {
    const dto = plainToInstance(ManualAssignDriverDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.drivers.manualAssignOrder(orderId, dto.driverId, dto.deliveryLat, dto.deliveryLng);
  }

  /** Customer retry after `no_driver_found` (capped; resets auto-assign attempts). */
  @Post('orders/:id/retry-assignment')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 15 } })
  @RequirePermissions('orders.write')
  async retryAssignment(@Req() req: RequestWithFirebase, @Param('id') orderId: string) {
    return this.drivers.retryAssignment(req.firebaseUid!, orderId);
  }
}
