import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';

@ApiTags('Well-Known')
@Controller('.well-known')
export class WellKnownController {
  constructor(private readonly configService: ConfigService) {}

  @Get('assetlinks.json')
  @ApiOperation({ summary: 'Android App Links verification file' })
  @ApiResponse({
    status: 200,
    description: 'Returns assetlinks.json for Android deep linking',
  })
  assetLinks() {
    return [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: this.configService.get<string>('ANDROID_PACKAGE_NAME'),
          sha256_cert_fingerprints: [
            this.configService.get<string>('ANDROID_SHA256_FINGERPRINT'),
          ],
        },
      },
    ];
  }
}
