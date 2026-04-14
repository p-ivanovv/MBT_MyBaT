import { ClassSerializerInterceptor, Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SwaggerModule } from '@nestjs/swagger';
import { PassportModule } from '@nestjs/passport';
import { APP_INTERCEPTOR } from '@nestjs/core';

import { UsersModule } from './users/users.module';
import { typeOrmAsyncConfig } from './config';
import { AuthModule } from './auth/auth.module';
import { SeedingModule } from './seeding/seeding.module';
import { SendgridModule } from './sendgrid/sendgrid.module';
import { RelativesModule } from './relatives/relatives.module';
import { FoodModule } from './food/food.module';
import { SosModule } from './sos/sos.module';
import { WellKnownModule } from './well-known/well-known.module';
import { InviteRedirectModule } from './invite-redirect/invite-redirect.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync(typeOrmAsyncConfig),
    PassportModule,
    SwaggerModule,
    UsersModule,
    AuthModule,
    SeedingModule,
    SendgridModule,
    RelativesModule,
    FoodModule,
    SosModule,
    WellKnownModule,
    InviteRedirectModule,
  ],
  controllers: [],
  providers: [
    {
      provide: APP_INTERCEPTOR,
      useClass: ClassSerializerInterceptor,
    },
  ],
})
export class AppModule {}
