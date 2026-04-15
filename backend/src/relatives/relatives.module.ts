import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule } from '@nestjs/config';
import { UserEntity } from 'src/users/entities';
import { MailtrapModule } from 'src/mailtrap/mailtrap.module';

import { RelativeEntity, InvitationEntity } from './entities';
import { RelativesService } from './relatives.service';
import { RelativesController } from './relatives.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([RelativeEntity, UserEntity, InvitationEntity]),
    MailtrapModule,
    ConfigModule,
  ],
  providers: [RelativesService],
  controllers: [RelativesController],
  exports: [RelativesService],
})
export class RelativesModule {}
