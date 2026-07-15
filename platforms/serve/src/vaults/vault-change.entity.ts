import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'vault_changes' })
export class VaultChange {
  /** Monotonic server cursor; this is an identifier, not password metadata. */
  @PrimaryGeneratedColumn('increment', { type: 'bigint' })
  sequence!: string;

  @Column('uuid')
  vaultId!: string;

  @Column({ unique: true, length: 128 })
  changeId!: string;

  @Column('uuid')
  deviceId!: string;

  /** Opaque client-generated encrypted change package. */
  @Column('text')
  ciphertext!: string;

  /** Opaque client-generated Ed25519 signature; validation arrives with device enrollment. */
  @Column('text')
  signature!: string;
}
