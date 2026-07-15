import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { Device } from '../devices/device.entity';
import { VaultChange } from './vault-change.entity';
import { Vault } from './vault.entity';
import { VaultsController } from './vaults.controller';
import { VaultsService } from './vaults.service';

@Module({
  imports: [AuthModule, TypeOrmModule.forFeature([Vault, VaultChange, Device])],
  controllers: [VaultsController],
  providers: [VaultsService]
})
export class VaultsModule {}
