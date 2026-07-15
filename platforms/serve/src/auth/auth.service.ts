import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { Repository } from 'typeorm';
import { InjectRepository } from '@nestjs/typeorm';
import { CredentialsDto } from './auth.dto';
import { User } from './user.entity';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    private readonly jwt: JwtService
  ) {}

  async register(credentials: CredentialsDto): Promise<{ accessToken: string }> {
    const loginName = credentials.loginName.trim().toLocaleLowerCase();
    if (await this.users.findOneBy({ loginName })) {
      throw new ConflictException('账号已存在。');
    }
    const user = this.users.create({
      loginName,
      passwordHash: await argon2.hash(credentials.password, { type: argon2.argon2id })
    });
    await this.users.save(user);
    return { accessToken: await this.issue(user.id) };
  }

  async login(credentials: CredentialsDto): Promise<{ accessToken: string }> {
    const loginName = credentials.loginName.trim().toLocaleLowerCase();
    const user = await this.users.findOneBy({ loginName });
    if (!user || !(await argon2.verify(user.passwordHash, credentials.password))) {
      throw new UnauthorizedException('账号或密码错误。');
    }
    return { accessToken: await this.issue(user.id) };
  }

  async verify(accessToken: string): Promise<string> {
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string }>(accessToken);
      return payload.sub;
    } catch {
      throw new UnauthorizedException('登录状态无效。');
    }
  }

  private issue(userID: string): Promise<string> {
    return this.jwt.signAsync({ sub: userID });
  }
}
