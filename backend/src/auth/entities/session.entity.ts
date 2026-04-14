import { UserEntity } from 'src/users/entities';
import { Column, Entity, ManyToOne, PrimaryColumn } from 'typeorm';

@Entity('session')
export class SessionEntity {
  @PrimaryColumn()
  id: string;

  @Column()
  refreshToken: string;

  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  @ManyToOne(() => UserEntity, (user) => user.sessions, {
    onDelete: 'CASCADE',
  })
  user: UserEntity;
}
