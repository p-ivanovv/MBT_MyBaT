import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { JwtAuthGuard, RolesGuard } from 'src/auth/guards';
import { RequestWithUser, UserRoles } from 'src/common';
import { Role } from 'src/auth/decorators';

import { FoodService } from './food.service';
import { CreateFoodDto } from './dtos';

@ApiTags('Food')
@ApiBearerAuth('AccessToken')
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('food')
export class FoodController {
  constructor(private readonly foodService: FoodService) {}

  @Role(UserRoles.User)
  @Post('preferred')
  @ApiOperation({ summary: 'Add a preferred food for the blind user' })
  @ApiResponse({ status: 201, description: 'Preferred food added' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async addPreferred(
    @Request() req: RequestWithUser,
    @Body() dto: CreateFoodDto,
  ) {
    return this.foodService.addPreferredFood(req.user.id, dto);
  }

  @Role(UserRoles.User)
  @Get('preferred')
  @ApiOperation({ summary: 'Get all preferred foods for the blind user' })
  @ApiResponse({ status: 200, description: 'List of preferred foods' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async getPreferred(@Request() req: RequestWithUser) {
    return this.foodService.getPreferredFoods(req.user.id);
  }

  @Role(UserRoles.User)
  @Delete('preferred/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete a preferred food by ID' })
  @ApiParam({ name: 'id', description: 'UUID of the preferred food entry' })
  @ApiResponse({ status: 204, description: 'Preferred food deleted' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async removePreferred(
    @Param('id') id: string,
    @Request() req: RequestWithUser,
  ) {
    return this.foodService.removePreferredFood(id, req.user.id);
  }

  @Role(UserRoles.User)
  @Post('allergies')
  @ApiOperation({ summary: 'Add an allergy food for the blind user' })
  @ApiResponse({ status: 201, description: 'Allergy food added' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async addAllergy(
    @Request() req: RequestWithUser,
    @Body() dto: CreateFoodDto,
  ) {
    return this.foodService.addAllergyFood(req.user.id, dto);
  }

  @Role(UserRoles.User)
  @Get('allergies')
  @ApiOperation({ summary: 'Get all allergy foods for the blind user' })
  @ApiResponse({ status: 200, description: 'List of allergy foods' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async getAllergies(@Request() req: RequestWithUser) {
    return this.foodService.getAllergyFoods(req.user.id);
  }

  @Role(UserRoles.User)
  @Delete('allergies/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete an allergy food by ID' })
  @ApiParam({ name: 'id', description: 'UUID of the allergy food entry' })
  @ApiResponse({ status: 204, description: 'Allergy food deleted' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  async removeAllergy(
    @Param('id') id: string,
    @Request() req: RequestWithUser,
  ) {
    return this.foodService.removeAllergyFood(id, req.user.id);
  }
}
