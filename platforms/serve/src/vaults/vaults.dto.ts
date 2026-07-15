import { IsOptional, IsString, Length, Matches } from 'class-validator';

const base64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

export class CreateVaultDto {
  @IsString()
  @Length(24, 2_000_000)
  @Matches(base64Pattern)
  encryptedKeyEnvelope!: string;
}

export class AppendChangeDto {
  @IsString()
  @Length(1, 128)
  changeId!: string;

  @IsString()
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
  deviceId!: string;

  @IsString()
  @Length(24, 2_000_000)
  @Matches(base64Pattern)
  ciphertext!: string;

  @IsString()
  @Length(24, 16_384)
  @Matches(base64Pattern)
  signature!: string;
}

export class ListChangesQueryDto {
  @IsOptional()
  @IsString()
  @Matches(/^\d+$/)
  after?: string;
}
