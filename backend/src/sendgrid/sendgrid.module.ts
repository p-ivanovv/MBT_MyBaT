import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { SendgridService } from './sendgrid.service';

@Module({
  controllers: [],
  imports: [ConfigModule],
  providers: [SendgridService],
  exports: [SendgridService],
})
export class SendgridModule {}
