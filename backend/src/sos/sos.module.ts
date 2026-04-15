import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserEntity } from 'src/users/entities';
import { RelativeEntity } from 'src/relatives/entities';
import { MailtrapModule } from 'src/mailtrap/mailtrap.module';

import { SosService } from './sos.service';
import { SosController } from './sos.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([RelativeEntity, UserEntity]),
    MailtrapModule,
  ],
  providers: [SosService],
  controllers: [SosController],
})
export class SosModule {}
