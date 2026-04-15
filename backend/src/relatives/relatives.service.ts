import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { nanoid } from 'nanoid';
import { Repository } from 'typeorm';
import { UserEntity } from 'src/users/entities';
import { UserRoles } from 'src/common';
import { MailtrapService } from 'src/mailtrap/mailtrap.service';
import { ConfigService } from '@nestjs/config';

import { RelativeEntity, InvitationEntity } from './entities';
import { CreateRelativeDto, InviteUserDto, AcceptInviteDto } from './dtos';
import { RelativesErrorCodes } from './errors';

const INVITE_EXPIRY_MS = 5 * 60 * 1000; // 5 minutes

@Injectable()
export class RelativesService {
  constructor(
    @InjectRepository(RelativeEntity)
    private readonly relativesRepository: Repository<RelativeEntity>,
    @InjectRepository(UserEntity)
    private readonly usersRepository: Repository<UserEntity>,
    @InjectRepository(InvitationEntity)
    private readonly invitationsRepository: Repository<InvitationEntity>,
    private readonly sendgridService: MailtrapService,
    private readonly configService: ConfigService,
  ) {}

  async create(relativeId: string, dto: CreateRelativeDto) {
    const existingUser = await this.usersRepository.findOne({
      where: { email: dto.email },
    });

    if (existingUser) {
      throw new BadRequestException(
        RelativesErrorCodes.BlindUserAlreadyExistsError,
      );
    }

    const user = await this.usersRepository.save(
      this.usersRepository.create({ ...dto, role: UserRoles.User }),
    );

    await this.relativesRepository.save(
      this.relativesRepository.create({ userId: user.id, relativeId }),
    );

    return user;
  }

  async findAllByUser(relativeId: string) {
    const links = await this.relativesRepository.find({
      where: { relativeId },
      relations: ['user'],
    });
    return links.map((l) => l.user);
  }

  async findRelativesOfUser(userId: string) {
    const links = await this.relativesRepository.find({
      where: { userId },
      relations: ['relative'],
    });
    return links.map((l) => l.relative);
  }

  async remove(relativeId: string, userId: string) {
    await this.relativesRepository.delete({ relativeId, userId });
  }

  async invite(relativeId: string, dto: InviteUserDto) {
    const blindUser = await this.usersRepository.findOne({
      where: { email: dto.email, role: UserRoles.User },
    });

    if (!blindUser) {
      throw new NotFoundException(RelativesErrorCodes.BlindUserNotFoundError);
    }

    const relative = await this.usersRepository.findOne({
      where: { id: relativeId },
    });

    const token = nanoid(32);
    const expiresAt = new Date(Date.now() + INVITE_EXPIRY_MS);

    await this.invitationsRepository.save(
      this.invitationsRepository.create({
        token,
        relativeId,
        invitedEmail: dto.email,
        expiresAt,
      }),
    );

    const deepLinkBase = this.configService.get<string>('DEEP_LINK_BASE_URL');
    const inviteUrl = `${deepLinkBase}/invite?token=${token}`;
    const relativeName =
      [relative.firstName, relative.lastName].filter(Boolean).join(' ') ||
      relative.email;

    await this.sendgridService.sendInvitation({
      email: dto.email,
      relativeName,
      inviteUrl,
    });
  }

  async acceptInvite(userId: string, dto: AcceptInviteDto) {
    const invitation = await this.invitationsRepository.findOne({
      where: { token: dto.token },
    });

    if (!invitation) {
      throw new BadRequestException(
        RelativesErrorCodes.InvitationNotFoundError,
      );
    }

    if (new Date() > invitation.expiresAt) {
      await this.invitationsRepository.delete({ id: invitation.id });
      throw new BadRequestException(RelativesErrorCodes.InvitationExpiredError);
    }

    const alreadyLinked = await this.relativesRepository.exists({
      where: { userId, relativeId: invitation.relativeId },
    });

    if (!alreadyLinked) {
      await this.relativesRepository.save(
        this.relativesRepository.create({
          userId,
          relativeId: invitation.relativeId,
        }),
      );
    }

    await this.invitationsRepository.delete({ id: invitation.id });
  }
}
