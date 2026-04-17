import { Controller, Get } from '@nestjs/common';

@Controller()
export class AppController {
  @Get()
  root() {
    return 'OK';
  }

  @Get('health')
  health() {
    return 'OK';
  }
}
