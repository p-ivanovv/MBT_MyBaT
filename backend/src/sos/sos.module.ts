import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserEntity } from 'src/users/entities';
import { RelativeEntity } from 'src/relatives/entities';
import { SendgridModule } from 'src/sendgrid/sendgrid.module';

import { SosService } from './sos.service';
import { SosController } from './sos.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([RelativeEntity, UserEntity]),
    SendgridModule,
  ],
  providers: [SosService],
  controllers: [SosController],
})
export class SosModule {}
