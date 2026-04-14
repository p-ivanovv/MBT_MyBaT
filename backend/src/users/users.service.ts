import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RegisterDto } from 'src/auth/dtos';
import { UserRoles } from 'src/common';

import { UserEntity } from './entities';
import { UserErrorCodes } from './errors';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly usersRepository: Repository<UserEntity>,
  ) {}

  async checkEmail(email: string) {
    return await this.usersRepository.exists({
      where: {
        email,
      },
    });
  }

  async create(dto: RegisterDto, role: UserRoles = UserRoles.Relative) {
    if (await this.checkEmail(dto.email)) {
      throw new BadRequestException(
        UserErrorCodes.UserWithThisEmailAlreadyCreatedError,
      );
    }

    const user = this.usersRepository.create({
      ...dto,
      role,
    });

    return await this.usersRepository.save(user);
  }

  async findOne(id: string) {
    return await this.usersRepository.findOne({
      where: {
        id,
      },
    });
  }

  async findOneOrFail(id: string) {
    const user = await this.findOne(id);

    if (!user) {
      throw new UnauthorizedException(UserErrorCodes.UserNotFoundError);
    }

    return user;
  }

  async findOneByEmail(email: string) {
    return await this.usersRepository.findOne({
      where: {
        email,
      },
    });
  }

  async findOneByEmailOrFail(email: string) {
    const user = await this.findOneByEmail(email);

    if (!user) {
      throw new UnauthorizedException(UserErrorCodes.UserNotFoundError);
    }

    return user;
  }

  async updateRefreshTokenVersion(userId: string) {
    return await this.usersRepository.increment(
      { id: userId },
      'refreshTokenVersion',
      1,
    );
  }
}
