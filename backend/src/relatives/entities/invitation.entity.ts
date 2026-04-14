import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { UserEntity } from 'src/users/entities';

@Entity('invitation')
export class InvitationEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  token: string;

  @Column()
  relativeId: string;

  @Column()
  invitedEmail: string;

  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'relativeId' })
  relative: UserEntity;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: string;
}
