import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserEntity } from 'src/users/entities';

import { SeedingService } from './seeding.service';

@Module({
  imports: [TypeOrmModule.forFeature([UserEntity])],
  providers: [SeedingService],
  exports: [SeedingService],
})
export class SeedingModule {}
