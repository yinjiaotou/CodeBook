import { IsString, Length, Matches } from 'class-validator';

export class CredentialsDto {
  @IsString()
  @Length(3, 320)
  loginName!: string;

  @IsString()
  @Length(12, 1024)
  password!: string;
}

export class AccessTokenDto {
  @IsString()
  @Matches(/^Bearer\s+.+$/)
  authorization!: string;
}
