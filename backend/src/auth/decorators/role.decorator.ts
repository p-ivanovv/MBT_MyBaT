import { Reflector } from '@nestjs/core';
import { UserRoles } from 'src/common';

export const Role = Reflector.createDecorator<UserRoles>();
