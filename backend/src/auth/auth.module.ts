import { Module } from '@nestjs/common';
import { UsersModule } from 'src/users/users.module';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserEntity } from 'src/users/entities';

import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { LocalAuthGuard } from './guards';
import { JwtStrategy, LocalStrategy, RefreshTokenStrategy } from './strategies';
import { SessionEntity } from './entities';

@Module({
  imports: [
    UsersModule,
    JwtModule,
    TypeOrmModule.forFeature([UserEntity, SessionEntity]),
  ],
  providers: [
    AuthService,
    LocalAuthGuard,
    LocalStrategy,
    JwtStrategy,
    RefreshTokenStrategy,
  ],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
