import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { SessionsService } from './sessions.service';

@Module({
  controllers: [AuthController],
  providers: [SessionsService],
  exports: [SessionsService],
})
export class AuthModule {}
