import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UserEntity } from 'src/users/entities';
import { RelativeEntity } from 'src/relatives/entities';
import { MailtrapService } from 'src/mailtrap/mailtrap.service';

import { SosDto } from './dtos/sos.dto';

@Injectable()
export class SosService {
  constructor(
    @InjectRepository(RelativeEntity)
    private readonly relativesRepository: Repository<RelativeEntity>,
    @InjectRepository(UserEntity)
    private readonly usersRepository: Repository<UserEntity>,
    private readonly sendgridService: MailtrapService,
  ) {}

  async triggerSos(userId: string, dto: SosDto) {
    const blindUser = await this.usersRepository.findOne({
      where: { id: userId },
    });

    const userName =
      [blindUser.firstName, blindUser.lastName].filter(Boolean).join(' ') ||
      blindUser.email;

    const links = await this.relativesRepository.find({
      where: { userId },
      relations: ['relative'],
    });

    const mapsUrl = `https://www.google.com/maps?q=${dto.latitude},${dto.longitude}`;
    const alertTime = new Date().toUTCString();

    await Promise.all(
      links.map((link) =>
        this.sendgridService.sendSos({
          email: link.relative.email,
          userName,
          latitude: dto.latitude,
          longitude: dto.longitude,
          alertTime,
          mapsUrl,
        }),
      ),
    );
  }
}
