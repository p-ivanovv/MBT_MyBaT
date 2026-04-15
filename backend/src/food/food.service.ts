import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { PreferredFoodEntity, AllergyFoodEntity } from './entities';
import { CreateFoodDto } from './dtos';

@Injectable()
export class FoodService {
  constructor(
    @InjectRepository(PreferredFoodEntity)
    private readonly preferredFoodRepository: Repository<PreferredFoodEntity>,
    @InjectRepository(AllergyFoodEntity)
    private readonly allergyFoodRepository: Repository<AllergyFoodEntity>,
  ) {}

  async addPreferredFood(userId: string, dto: CreateFoodDto) {
    return this.preferredFoodRepository.save(
      this.preferredFoodRepository.create({ userId, name: dto.name }),
    );
  }

  async getPreferredFoods(userId: string) {
    return this.preferredFoodRepository.find({ where: { userId } });
  }

  async removePreferredFood(id: string, userId: string) {
    await this.preferredFoodRepository.delete({ id, userId });
  }

  async addAllergyFood(userId: string, dto: CreateFoodDto) {
    return this.allergyFoodRepository.save(
      this.allergyFoodRepository.create({ userId, name: dto.name }),
    );
  }

  async getAllergyFoods(userId: string) {
    return this.allergyFoodRepository.find({ where: { userId } });
  }

  async removeAllergyFood(id: string, userId: string) {
    await this.allergyFoodRepository.delete({ id, userId });
  }
}
