import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class CreateFoodDto {
  @ApiProperty()
  @IsNotEmpty()
  @IsString()
  name: string;
}
