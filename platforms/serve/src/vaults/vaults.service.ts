import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { createPublicKey, verify } from 'crypto';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AppendChangeDto, CreateVaultDto } from './vaults.dto';
import { Device } from '../devices/device.entity';
import { VaultChange } from './vault-change.entity';
import { Vault } from './vault.entity';

@Injectable()
export class VaultsService {
  constructor(
    @InjectRepository(Vault) private readonly vaults: Repository<Vault>,
    @InjectRepository(VaultChange) private readonly changes: Repository<VaultChange>,
    @InjectRepository(Device) private readonly devices: Repository<Device>
  ) {}

  async createVault(userID: string, dto: CreateVaultDto): Promise<Vault> {
    this.assertOpaqueBase64(dto.encryptedKeyEnvelope);
    return this.vaults.save(this.vaults.create({ ownerId: userID, encryptedKeyEnvelope: dto.encryptedKeyEnvelope }));
  }

  async listVaults(userID: string): Promise<Vault[]> {
    return this.vaults.find({ where: { ownerId: userID }, order: { id: 'ASC' } });
  }

  async appendChange(userID: string, vaultID: string, dto: AppendChangeDto): Promise<VaultChange> {
    await this.assertOwnership(userID, vaultID);
    this.assertOpaqueBase64(dto.ciphertext);
    this.assertOpaqueBase64(dto.signature);
    const existing = await this.changes.findOneBy({ changeId: dto.changeId });
    if (existing) {
      if (existing.vaultId === vaultID && existing.deviceId === dto.deviceId
        && existing.ciphertext === dto.ciphertext && existing.signature === dto.signature) return existing;
      throw new ConflictException('变更 ID 已被使用。');
    }
    await this.assertValidDeviceSignature(userID, vaultID, dto);
    return this.changes.save(this.changes.create({ vaultId: vaultID, ...dto }));
  }

  async listChanges(userID: string, vaultID: string, after?: string): Promise<VaultChange[]> {
    await this.assertOwnership(userID, vaultID);
    const changes = await this.changes.find({ where: { vaultId: vaultID }, order: { sequence: 'ASC' } });
    return after ? changes.filter((change) => BigInt(change.sequence) > BigInt(after)) : changes;
  }

  private async assertOwnership(userID: string, vaultID: string): Promise<void> {
    const vault = await this.vaults.findOneBy({ id: vaultID });
    if (!vault) throw new NotFoundException('密码库不存在。');
    if (vault.ownerId !== userID) throw new ForbiddenException('无权访问此密码库。');
  }

  private assertOpaqueBase64(value: string): void {
    if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
      throw new BadRequestException('密文格式无效。');
    }
  }

  private async assertValidDeviceSignature(userID: string, vaultID: string, dto: AppendChangeDto): Promise<void> {
    const device = await this.devices.findOneBy({ id: dto.deviceId });
    if (!device || device.ownerId !== userID || device.revokedAt) {
      throw new ForbiddenException('设备无权写入此密码库。');
    }
    const rawPublicKey = Buffer.from(device.publicSigningKey, 'base64');
    const signature = Buffer.from(dto.signature, 'base64');
    // UUIDs are protocol identifiers, not display strings. The client signs their
    // canonical lowercase RFC 4122 representation, while HTTP routers preserve
    // whatever casing was used in the request path/body.
    const message = Buffer.from(
      `pwdlock.sync.v1\u0000${vaultID.toLowerCase()}\u0000${dto.changeId.toLowerCase()}\u0000${dto.ciphertext}`,
      'utf8'
    );
    const spkiPrefix = Buffer.from('302a300506032b6570032100', 'hex');
    const publicKey = createPublicKey({ key: Buffer.concat([spkiPrefix, rawPublicKey]), format: 'der', type: 'spki' });
    if (!verify(null, message, publicKey, signature)) throw new ForbiddenException('密文签名无效。');
  }
}
