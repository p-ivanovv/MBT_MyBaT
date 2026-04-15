import { Controller, Get, Request, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { JwtAuthGuard, RolesGuard } from 'src/auth/guards';
import { RequestWithUser, UserRoles } from 'src/common';
import { RelativesService } from 'src/relatives/relatives.service';
import { Role } from 'src/auth/decorators';

import { UsersService } from './users.service';

@ApiTags('Users')
@ApiBearerAuth('AccessToken')
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('users')
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly relativesService: RelativesService,
  ) {}

  @Get('me')
  @ApiOperation({ summary: 'Get the currently authenticated user profile' })
  @ApiResponse({ status: 200, description: 'Returns the current user object' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async getMe(@Request() req: RequestWithUser) {
    return req.user;
  }

  @Role(UserRoles.User)
  @Get('my-relatives')
  @ApiOperation({
    summary: 'Get all relatives linked to the current blind user',
  })
  @ApiResponse({
    status: 200,
    description: 'List of relatives for the blind user',
  })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async getMyRelatives(@Request() req: RequestWithUser) {
    return this.relativesService.findRelativesOfUser(req.user.id);
  }
}
