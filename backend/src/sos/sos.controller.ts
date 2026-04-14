import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { JwtAuthGuard, RolesGuard } from 'src/auth/guards';
import { RequestWithUser, UserRoles } from 'src/common';
import { Role } from 'src/auth/decorators';

import { SosService } from './sos.service';
import { SosDto } from './dtos/sos.dto';

@ApiTags('SOS')
@ApiBearerAuth('AccessToken')
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('sos')
export class SosController {
  constructor(private readonly sosService: SosService) {}

  @Post()
  @Role(UserRoles.User)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary:
      'Trigger SOS alert — sends email with GPS location to all linked relatives',
  })
  @ApiResponse({ status: 204, description: 'SOS emails sent to all relatives' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async triggerSos(@Request() req: RequestWithUser, @Body() dto: SosDto) {
    return this.sosService.triggerSos(req.user.id, dto);
  }
}
