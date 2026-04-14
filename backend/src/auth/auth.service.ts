import { Injectable } from '@nestjs/common';
import { UsersService } from 'src/users/users.service';
import * as argon2 from 'argon2';
import { UserEntity } from 'src/users/entities';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import ms from 'ms';
import { nanoid } from 'nanoid';

import { RegisterDto } from './dtos';
import { SessionEntity } from './entities';

@Injectable()
export class AuthService {
  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    @InjectRepository(SessionEntity)
    private readonly sessionsRepository: Repository<SessionEntity>,
  ) {}

  async register(dto: RegisterDto) {
    const user = await this.usersService.create(dto);
    return await this.login(user);
  }

  async generateTokens(payload: any) {
    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(payload, {
        secret: this.configService.get('JWT_ACCESS_SECRET'),
        expiresIn: this.configService.get('JWT_ACCESS_EXPIRES_IN'),
      }),
      this.jwtService.signAsync(payload, {
        secret: this.configService.get('JWT_REFRESH_SECRET'),
        expiresIn: this.configService.get('JWT_REFRESH_EXPIRES_IN'),
      }),
    ]);

    return { accessToken, refreshToken };
  }

  async refreshTokens(session: SessionEntity) {
    const tokens = await this.generateTokens({
      id: session?.user.id,
      email: session?.user.email,
      sessionId: session?.id,
    });

    const expiresAt = new Date(
      Date.now() + ms(this.configService.get('JWT_REFRESH_EXPIRES_IN')),
    );

    await this.sessionsRepository.update(session, {
      expiresAt,
      refreshToken: tokens.refreshToken,
    });

    return tokens;
  }

  async createSession(
    sessionId: string,
    user: UserEntity,
    refreshToken: string,
  ) {
    const session = this.sessionsRepository.create({
      id: sessionId,
      user,
      refreshToken: refreshToken,
      expiresAt: new Date(
        Date.now() + ms(this.configService.get('JWT_REFRESH_EXPIRES_IN')),
      ),
    });

    return await this.sessionsRepository.save(session);
  }

  async login(user: UserEntity) {
    const sessionId = nanoid();

    const payload = {
      id: user.id,
      email: user.email,
      sessionId,
    };

    const tokens = await this.generateTokens(payload);

    await this.createSession(sessionId, user, tokens.refreshToken);

    return tokens;
  }

  async validateUser(email: string, password: string): Promise<any> {
    const user = await this.usersService.findOneByEmailOrFail(email);

    if (await argon2.verify(user.password, password)) {
      return user;
    }
    return null;
  }
}
