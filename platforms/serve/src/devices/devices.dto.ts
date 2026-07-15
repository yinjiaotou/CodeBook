import { IsString, Length, Matches } from 'class-validator';

export class RegisterDeviceDto {
  @IsString()
  @Length(1, 120)
  label!: string;

  @IsString()
  @Matches(/^[A-Za-z0-9+/]{43}=$/)
  publicSigningKey!: string;
}
