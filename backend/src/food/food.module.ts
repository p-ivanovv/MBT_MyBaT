import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { PreferredFoodEntity, AllergyFoodEntity } from './entities';
import { FoodService } from './food.service';
import { FoodController } from './food.controller';

@Module({
  imports: [TypeOrmModule.forFeature([PreferredFoodEntity, AllergyFoodEntity])],
  providers: [FoodService],
  controllers: [FoodController],
})
export class FoodModule {}
