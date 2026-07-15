import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { generateKeyPairSync, sign } from 'crypto';
import { VaultsService } from './vaults.service';

describe('VaultsService', () => {
  const vaultRepository = {
    create: jest.fn((value) => value),
    save: jest.fn(async (value) => value),
    find: jest.fn(),
    findOneBy: jest.fn()
  };
  const changeRepository = {
    create: jest.fn((value) => value),
    save: jest.fn(async (value) => value),
    find: jest.fn(),
    findOneBy: jest.fn()
  };
  const deviceRepository = { findOneBy: jest.fn() };
  const service = new VaultsService(vaultRepository as never, changeRepository as never, deviceRepository as never);
  const keys = generateKeyPairSync('ed25519');
  const publicKeyDer = keys.publicKey.export({ format: 'der', type: 'spki' });
  const publicSigningKey = publicKeyDer.subarray(12).toString('base64');

  const signedChange = (changeId: string, ciphertext: string) => ({
    changeId,
    deviceId: 'device-1',
    ciphertext,
    signature: sign(null, Buffer.from(`pwdlock.sync.v1\u0000vault-1\u0000${changeId}\u0000${ciphertext}`, 'utf8'), keys.privateKey).toString('base64')
  });

  beforeEach(() => {
    jest.clearAllMocks();
    vaultRepository.findOneBy.mockResolvedValue({ id: 'vault-1', ownerId: 'user-1' });
    deviceRepository.findOneBy.mockResolvedValue({ id: 'device-1', ownerId: 'user-1', publicSigningKey });
    changeRepository.findOneBy.mockResolvedValue(undefined);
  });

  it('stores a client ciphertext unchanged and rejects non-base64 payloads', async () => {
    const ciphertext = Buffer.from('client-encrypted-payload').toString('base64');
    await service.appendChange('user-1', 'vault-1', signedChange('change-1', ciphertext));

    expect(changeRepository.save).toHaveBeenCalledWith(expect.objectContaining({ ciphertext }));
    await expect(service.appendChange('user-1', 'vault-1', {
      ...signedChange('change-2', ciphertext), ciphertext: 'not base64!'
    })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('does not expose or append encrypted changes for another account', async () => {
    vaultRepository.findOneBy.mockResolvedValue({ id: 'vault-1', ownerId: 'user-2' });

    await expect(service.appendChange('user-1', 'vault-1', signedChange(
      'change-1', Buffer.from('client-encrypted-payload').toString('base64')
    ))).rejects.toBeInstanceOf(ForbiddenException);
    expect(changeRepository.save).not.toHaveBeenCalled();
  });

  it('rejects a ciphertext when the device signature does not cover the exact bytes', async () => {
    const ciphertext = Buffer.from('client-encrypted-payload').toString('base64');
    const change = signedChange('change-1', ciphertext);

    await expect(service.appendChange('user-1', 'vault-1', {
      ...change,
      ciphertext: Buffer.from('tampered-payload').toString('base64')
    })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('rejects writes from a revoked device without altering stored history', async () => {
    deviceRepository.findOneBy.mockResolvedValue({
      id: 'device-1', ownerId: 'user-1', publicSigningKey, revokedAt: new Date()
    });
    const ciphertext = Buffer.from('client-encrypted-payload').toString('base64');

    await expect(service.appendChange('user-1', 'vault-1', signedChange('change-1', ciphertext)))
      .rejects.toBeInstanceOf(ForbiddenException);
    expect(changeRepository.save).not.toHaveBeenCalled();
  });
});
