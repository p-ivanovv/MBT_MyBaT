import { MigrationInterface, QueryRunner } from 'typeorm';

export class Relatives1774619405303 implements MigrationInterface {
  name = 'Relatives1774619405303';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TABLE "relative" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" uuid NOT NULL,
        "relativeId" uuid NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "UQ_relative_user_relative" UNIQUE ("userId", "relativeId"),
        CONSTRAINT "PK_relative_id" PRIMARY KEY ("id")
      )`,
    );
    await queryRunner.query(
      `ALTER TABLE "relative"
        ADD CONSTRAINT "FK_relative_userId"
        FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE`,
    );
    await queryRunner.query(
      `ALTER TABLE "relative"
        ADD CONSTRAINT "FK_relative_relativeId"
        FOREIGN KEY ("relativeId") REFERENCES "user"("id") ON DELETE CASCADE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "relative" DROP CONSTRAINT "FK_relative_relativeId"`,
    );
    await queryRunner.query(
      `ALTER TABLE "relative" DROP CONSTRAINT "FK_relative_userId"`,
    );
    await queryRunner.query(`DROP TABLE "relative"`);
  }
}
