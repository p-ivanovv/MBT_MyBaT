import { MigrationInterface, QueryRunner } from "typeorm";

export class Users1712918271756 implements MigrationInterface {
    name = 'Users1712918271756'

    public async up(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`ALTER TABLE "user" RENAME COLUMN "isVerified" TO "role"`);
        await queryRunner.query(`ALTER TABLE "user" DROP COLUMN "role"`);
        await queryRunner.query(`ALTER TABLE "user" ADD "role" character varying NOT NULL DEFAULT 'user'`);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`ALTER TABLE "user" DROP COLUMN "role"`);
        await queryRunner.query(`ALTER TABLE "user" ADD "role" boolean NOT NULL DEFAULT false`);
        await queryRunner.query(`ALTER TABLE "user" RENAME COLUMN "role" TO "isVerified"`);
    }

}
