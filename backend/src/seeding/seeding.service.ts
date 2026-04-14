import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { UserRoles } from 'src/common';
import { UserEntity } from 'src/users/entities';
import { Repository } from 'typeorm';

@Injectable()
export class SeedingService {
  private readonly logger = new Logger(SeedingService.name);

  constructor(
    @InjectRepository(UserEntity)
    private readonly usersRepository: Repository<UserEntity>,
    private readonly configService: ConfigService,
  ) {}

  async seed() {
    this.logger.log('Seeding started');

    const isAdminExists = await this.usersRepository.findOne({
      where: {
        email: this.configService.get<string>('DEFAULT_ADMIN_ADDRESS'),
      },
    });

    if (isAdminExists) {
      this.logger.log('Admin user already exists');
      return;
    }

    this.logger.log('Seeding admin user');
    await this.usersRepository.save({
      email: this.configService.get<string>('DEFAULT_ADMIN_ADDRESS'),
      password: this.configService.get<string>('DEFAULT_ADMIN_PASSWORD'),
      role: UserRoles.Admin,
    });

    this.logger.log('Admin user seeded');
    this.logger.log('Seeding complete');
  }
}
