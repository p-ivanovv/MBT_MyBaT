import {
  Column,
  Entity,
  CreateDateColumn,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
  OneToMany,
} from 'typeorm';
import { Exclude } from 'class-transformer';
import { UserRoles } from 'src/common';
import { SessionEntity } from 'src/auth/entities';

@Entity('user')
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({
    nullable: true,
  })
  firstName: string;

  @Column({
    nullable: true,
  })
  lastName: string;

  @Column({
    unique: true,
  })
  email: string;

  @Exclude()
  @Column({
    nullable: true,
  })
  password: string;

  @Column({
    enum: UserRoles,
    default: UserRoles.User,
  })
  role: UserRoles;

  @OneToMany(() => SessionEntity, (session) => session.user, {
    nullable: true,
    cascade: true,
  })
  sessions: SessionEntity[];

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: string;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: string;
}
