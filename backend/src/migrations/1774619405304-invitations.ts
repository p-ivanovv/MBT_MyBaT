import { MigrationInterface, QueryRunner } from 'typeorm';

export class Invitations1774619405304 implements MigrationInterface {
  name = 'Invitations1774619405304';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TABLE "invitation" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "token" character varying NOT NULL,
        "relativeId" uuid NOT NULL,
        "invitedEmail" character varying NOT NULL,
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "UQ_invitation_token" UNIQUE ("token"),
        CONSTRAINT "PK_invitation_id" PRIMARY KEY ("id")
      )`,
    );
    await queryRunner.query(
      `ALTER TABLE "invitation"
        ADD CONSTRAINT "FK_invitation_relativeId"
        FOREIGN KEY ("relativeId") REFERENCES "user"("id") ON DELETE CASCADE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "invitation" DROP CONSTRAINT "FK_invitation_relativeId"`,
    );
    await queryRunner.query(`DROP TABLE "invitation"`);
  }
}
