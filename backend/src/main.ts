import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

import { AppModule } from './app.module';
import { SeedingService } from './seeding/seeding.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors({ origin: true, credentials: true });
  app.setGlobalPrefix('api', { exclude: ['invite', '.well-known/assetlinks.json'] });
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidUnknownValues: false,
      transformOptions: {
        enableImplicitConversion: true,
      },
    }),
  );

  const configService = app.get(ConfigService);

  const nodeEnv = configService.get<string>('ENV');

  if (nodeEnv === 'DEV') {
    const config = new DocumentBuilder()
      .setTitle('My Bat API')
      .setVersion('1.0')
      .addBearerAuth({ type: 'http' }, 'AccessToken')
      .addBearerAuth({ type: 'http' }, 'RefreshToken')
      .build();

    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('api/docs', app, document);
  }

  const port = configService.get<number>('PORT');

  const seedingService = app.get(SeedingService);
  await seedingService.seed();

  await app.listen(port || 3000);
}

void bootstrap();
