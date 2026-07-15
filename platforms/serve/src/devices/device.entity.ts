import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'devices' })
export class Device {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column('uuid')
  ownerId!: string;

  /** Raw 32-byte Ed25519 public key, base64 encoded by the client. */
  @Column({ length: 64 })
  publicSigningKey!: string;

  @Column({ length: 120 })
  label!: string;

  /** A revoked public key remains auditable but can no longer append changes. */
  @Column({ type: 'timestamptz', nullable: true })
  revokedAt!: Date | null;
}
