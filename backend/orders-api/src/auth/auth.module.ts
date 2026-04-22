import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { PhonePasswordController } from './phone-password.controller';
import { FirebaseLoginController } from './firebase-login.controller';
import { FirebaseLoginService } from './firebase-login.service';
import { PhonePasswordService } from './phone-password.service';
import { SessionsService } from './sessions.service';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [UsersModule],
  controllers: [AuthController, PhonePasswordController, FirebaseLoginController],
  providers: [SessionsService, PhonePasswordService, FirebaseLoginService],
  exports: [SessionsService, PhonePasswordService, FirebaseLoginService],
})
export class AuthModule {}
