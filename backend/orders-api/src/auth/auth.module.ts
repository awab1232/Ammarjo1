import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { PhonePasswordController } from './phone-password.controller';
import { PhonePasswordService } from './phone-password.service';
import { SessionsService } from './sessions.service';

@Module({
  controllers: [AuthController, PhonePasswordController],
  providers: [SessionsService, PhonePasswordService],
  exports: [SessionsService, PhonePasswordService],
})
export class AuthModule {}
