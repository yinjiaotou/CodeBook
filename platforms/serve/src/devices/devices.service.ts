import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RegisterDeviceDto } from './devices.dto';
import { Device } from './device.entity';

@Injectable()
export class DevicesService {
  constructor(@InjectRepository(Device) private readonly devices: Repository<Device>) {}

  async register(userID: string, dto: RegisterDeviceDto): Promise<Device> {
    const decoded = Buffer.from(dto.publicSigningKey, 'base64');
    if (decoded.length !== 32) throw new BadRequestException('设备签名公钥无效。');
    return this.devices.save(this.devices.create({
      ownerId: userID,
      label: dto.label.trim(),
      publicSigningKey: dto.publicSigningKey,
      revokedAt: null
    }));
  }

  list(userID: string): Promise<Device[]> {
    return this.devices.find({ where: { ownerId: userID }, order: { id: 'ASC' } });
  }

  async revoke(userID: string, deviceID: string): Promise<void> {
    const device = await this.devices.findOneBy({ id: deviceID, ownerId: userID });
    if (!device) throw new NotFoundException('设备不存在。');
    if (!device.revokedAt) {
      device.revokedAt = new Date();
      await this.devices.save(device);
    }
  }
}
