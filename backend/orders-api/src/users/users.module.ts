import { Global, Module } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Global()
@Module({
  controllers: [UsersController],
  providers: [UsersService, FirebaseAuthGuard],
  exports: [UsersService],
})
export class UsersModule {}
