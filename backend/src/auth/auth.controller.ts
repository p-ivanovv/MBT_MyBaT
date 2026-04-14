import {
  Body,
  Controller,
  Post,
  Req,
  Request,
  UseGuards,
} from '@nestjs/common';
import { RequestWithUser, UserRoles } from 'src/common';
import {
  ApiBearerAuth,
  ApiBody,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';

import { LocalAuthGuard, RefreshAuthGuard } from './guards';
import { LoginDto, RegisterDto, RequestWithSession } from './dtos';
import { AuthService } from './auth.service';
import { Role } from './decorators';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Role(UserRoles.Relative)
  @Post('register')
  @ApiOperation({ summary: 'Register a new relative user' })
  @ApiResponse({ status: 201, description: 'User created successfully' })
  @ApiResponse({ status: 400, description: 'Validation error' })
  async register(@Body() dto: RegisterDto) {
    return await this.authService.register(dto);
  }

  @UseGuards(LocalAuthGuard)
  @ApiBody({ type: LoginDto })
  @Post('login')
  @ApiOperation({ summary: 'Log in and receive access + refresh tokens' })
  @ApiResponse({
    status: 200,
    description: 'Returns accessToken and refreshToken',
  })
  @ApiResponse({ status: 401, description: 'Invalid credentials' })
  async login(@Request() req: RequestWithUser) {
    return await this.authService.login(req.user);
  }

  @ApiBearerAuth('RefreshToken')
  @UseGuards(RefreshAuthGuard)
  @Post('refresh')
  @ApiOperation({ summary: 'Refresh access token using refresh token' })
  @ApiResponse({
    status: 200,
    description: 'Returns new accessToken and refreshToken',
  })
  @ApiResponse({ status: 401, description: 'Invalid or expired refresh token' })
  async refreshTokens(@Req() req: RequestWithSession) {
    return await this.authService.refreshTokens(req.user.session);
  }
}
