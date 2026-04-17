import { Controller, Get } from '@nestjs/common';

@Controller()
export class AppController {
  @Get()
  root() {
    return { status: 'API running' };
  }

  @Get('health')
  health() {
    return { ok: true };
  }

  @Get('api/health')
  apiHealth() {
    return { ok: true };
  }
}
