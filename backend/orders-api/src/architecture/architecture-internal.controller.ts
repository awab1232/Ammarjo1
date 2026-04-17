import { Controller, Get, UseGuards } from '@nestjs/common';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { ArchitectureHealthService } from './architecture-health.service';

@Controller('internal/architecture')
@UseGuards(InternalApiKeyGuard)
export class ArchitectureInternalController {
  constructor(private readonly health: ArchitectureHealthService) {}

  @Get('health')
  getHealth() {
    return this.health.getReport();
  }
}
