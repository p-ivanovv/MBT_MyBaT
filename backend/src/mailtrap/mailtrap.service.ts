import * as fs from 'fs';
import * as path from 'path';
import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MailtrapClient } from 'mailtrap';

import { MailtrapErrorCodes } from './errors';
import { ResetPasswordType, SendInvitationType, SendSosType, SetPasswordType } from './types';

@Injectable()
export class MailtrapService {
  private readonly logger = new Logger(MailtrapService.name);
  private readonly client: MailtrapClient;
  private readonly from: string;

  constructor(private readonly config: ConfigService) {
    const token = this.config.get<string>('MAILTRAP_API_TOKEN');
    this.client = new MailtrapClient({ token });
    this.from = this.config.get<string>('MAILTRAP_FROM');
  }

  async sendPasswordSetup(dto: SetPasswordType) {
    const html = `
      <p>Hi ${dto.username},</p>
      <p>Please set up your password by clicking the link below:</p>
      <p><a href="${dto.url}">Set Password</a></p>
    `;
    return await this.sendMail({
      to: dto.email,
      subject: 'Set up your password',
      html,
    });
  }

  async sendInvitation(dto: SendInvitationType) {
    const templatePath = path.join(
      process.cwd(),
      'templates',
      'invitation.html',
    );
    let html = fs.readFileSync(templatePath, 'utf-8');
    html = html
      .replace(/\{\{relativeName\}\}/g, dto.relativeName)
      .replace(/\{\{inviteUrl\}\}/g, dto.inviteUrl);

    return await this.sendMail({
      to: dto.email,
      subject: `${dto.relativeName} invited you to join MBT`,
      html,
    });
  }

  async sendSos(dto: SendSosType) {
    const templatePath = path.join(process.cwd(), 'templates', 'sos.html');
    let html = fs.readFileSync(templatePath, 'utf-8');
    html = html
      .replace(/\{\{userName\}\}/g, dto.userName)
      .replace(/\{\{latitude\}\}/g, String(dto.latitude))
      .replace(/\{\{longitude\}\}/g, String(dto.longitude))
      .replace(/\{\{alertTime\}\}/g, dto.alertTime)
      .replace(/\{\{mapsUrl\}\}/g, dto.mapsUrl);

    return await this.sendMail({
      to: dto.email,
      subject: `🚨 SOS Alert — ${dto.userName} needs help!`,
      html,
    });
  }

  private async sendMail({ to, subject, html }: { to: string; subject: string; html: string }) {
    try {
      await this.client.send({
        from: { email: this.from },
        to: [{ email: to }],
        subject,
        html,
      });
      this.logger.log(`Email sent to ${to}`);
    } catch (err) {
      this.logger.error('Failed to send email', err);
      throw new BadRequestException(MailtrapErrorCodes.ErrorWhileSendingEmail);
    }
  }
}
