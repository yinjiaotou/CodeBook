import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'vaults' })
export class Vault {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column('uuid')
  ownerId!: string;

  /** Client-created AES-GCM envelope. This service never decrypts it. */
  @Column('text')
  encryptedKeyEnvelope!: string;
}
