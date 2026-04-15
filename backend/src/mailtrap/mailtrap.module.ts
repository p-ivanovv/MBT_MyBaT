import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { MailtrapService } from './mailtrap.service';

@Module({
  controllers: [],
  imports: [ConfigModule],
  providers: [MailtrapService],
  exports: [MailtrapService],
})
export class MailtrapModule {}
