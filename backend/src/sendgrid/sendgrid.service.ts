import * as fs from 'fs';
import * as path from 'path';
import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MailDataRequired, MailService } from '@sendgrid/mail';

import { Templates } from './enum';
import { SendgridErrorCodes } from './errors';
import { ResetPasswordType, SendInvitationType, SendSosType, SetPasswordType } from './types';

@Injectable()
export class SendgridService {
  private readonly logger = new Logger(SendgridService.name);
  private readonly sgMail = new MailService();
  private readonly from: string;
  private readonly helpTemplateId = Templates.HelpTemplate;

  constructor(private readonly config: ConfigService) {
    const apiKey = this.config.get<string>('SENDGRID_API_KEY');
    this.sgMail.setApiKey(apiKey);
    this.from = this.config.get<string>('SENDGRID_FROM');
  }

  async sendPasswordSetup(dto: SetPasswordType) {
    const mail: MailDataRequired = {
      from: this.from,
      templateId: this.helpTemplateId,
      subject: '',
      to: dto.email,
      personalizations: [
        {
          to: {
            email: dto.email,
          },
          dynamicTemplateData: {
            username: dto.username,
            create_password_url: dto.url,
          },
        },
      ],
    };
    return await this.sendMail(mail);
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

    const mail: MailDataRequired = {
      from: this.from,
      to: dto.email,
      subject: `${dto.relativeName} invited you to join MBT`,
      html,
    };
    return await this.sendMail(mail);
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

    const mail: MailDataRequired = {
      from: this.from,
      to: dto.email,
      subject: `🚨 SOS Alert — ${dto.userName} needs help!`,
      html,
    };
    return await this.sendMail(mail);
  }

  private async sendMail(mail: MailDataRequired) {
    try {
      await this.sgMail.send(mail);
      this.logger.log(`Email sent to ${JSON.stringify(mail.to)}`);
    } catch (err) {
      this.logger.error('Failed to send email', err?.response?.body || err);
      throw new BadRequestException(SendgridErrorCodes.ErrorWhileSendingEmail);
    }
  }
}
