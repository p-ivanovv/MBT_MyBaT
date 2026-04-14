import { MigrationInterface, QueryRunner } from 'typeorm';

export class Food1774619405305 implements MigrationInterface {
  name = 'Food1774619405305';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TABLE "preferred_food" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" uuid NOT NULL,
        "name" character varying NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_preferred_food_id" PRIMARY KEY ("id")
      )`,
    );
    await queryRunner.query(
      `ALTER TABLE "preferred_food"
        ADD CONSTRAINT "FK_preferred_food_userId"
        FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE`,
    );

    await queryRunner.query(
      `CREATE TABLE "allergy_food" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" uuid NOT NULL,
        "name" character varying NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_allergy_food_id" PRIMARY KEY ("id")
      )`,
    );
    await queryRunner.query(
      `ALTER TABLE "allergy_food"
        ADD CONSTRAINT "FK_allergy_food_userId"
        FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "allergy_food" DROP CONSTRAINT "FK_allergy_food_userId"`,
    );
    await queryRunner.query(`DROP TABLE "allergy_food"`);

    await queryRunner.query(
      `ALTER TABLE "preferred_food" DROP CONSTRAINT "FK_preferred_food_userId"`,
    );
    await queryRunner.query(`DROP TABLE "preferred_food"`);
  }
}
