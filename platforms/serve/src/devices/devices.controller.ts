import { Body, Controller, Delete, Get, HttpCode, Param, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthenticatedRequest } from '../auth/auth.guard';
import { RegisterDeviceDto } from './devices.dto';
import { DevicesService } from './devices.service';

@Controller('devices')
@UseGuards(AuthGuard)
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @Post()
  register(@Req() request: AuthenticatedRequest, @Body() dto: RegisterDeviceDto) {
    return this.devices.register(request.userID, dto);
  }

  @Get()
  list(@Req() request: AuthenticatedRequest) {
    return this.devices.list(request.userID);
  }

  @Delete(':deviceID')
  @HttpCode(204)
  revoke(@Req() request: AuthenticatedRequest, @Param('deviceID') deviceID: string): Promise<void> {
    return this.devices.revoke(request.userID, deviceID);
  }
}
