import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from './auth/auth.module';
import { User } from './auth/user.entity';
import { DevicesModule } from './devices/devices.module';
import { Device } from './devices/device.entity';
import { VaultChange } from './vaults/vault-change.entity';
import { Vault } from './vaults/vault.entity';
import { VaultsModule } from './vaults/vaults.module';

if (process.env.NODE_ENV === 'production' && (process.env.JWT_SECRET?.length ?? 0) < 32) {
  throw new Error('Production requires a JWT_SECRET of at least 32 characters.');
}

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL,
      entities: [User, Device, Vault, VaultChange],
      // Remote databases are changed only through reviewed SQL migrations. Schema
      // synchronization would require the runtime account to own production tables.
      synchronize: process.env.TYPEORM_SYNCHRONIZE === 'true'
    }),
    AuthModule,
    DevicesModule,
    VaultsModule
  ]
})
export class AppModule {}
