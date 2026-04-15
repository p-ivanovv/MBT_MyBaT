import { ApiProperty } from '@nestjs/swagger';
import { IsNumber } from 'class-validator';

export class SosDto {
  @ApiProperty({ example: 42.6977 })
  @IsNumber()
  latitude: number;

  @ApiProperty({ example: 23.3219 })
  @IsNumber()
  longitude: number;
}
