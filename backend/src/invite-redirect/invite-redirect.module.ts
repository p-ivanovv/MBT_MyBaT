import { Module } from '@nestjs/common';

import { InviteRedirectController } from './invite-redirect.controller';

@Module({
  controllers: [InviteRedirectController],
})
export class InviteRedirectModule {}
