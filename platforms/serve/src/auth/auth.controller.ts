import { Body, Controller, Post } from '@nestjs/common';
import { CredentialsDto } from './auth.dto';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  register(@Body() credentials: CredentialsDto): Promise<{ accessToken: string }> {
    return this.auth.register(credentials);
  }

  @Post('login')
  login(@Body() credentials: CredentialsDto): Promise<{ accessToken: string }> {
    return this.auth.login(credentials);
  }
}
