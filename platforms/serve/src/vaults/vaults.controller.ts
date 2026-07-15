import { Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthenticatedRequest } from '../auth/auth.guard';
import { AppendChangeDto, CreateVaultDto, ListChangesQueryDto } from './vaults.dto';
import { VaultsService } from './vaults.service';

@Controller('vaults')
@UseGuards(AuthGuard)
export class VaultsController {
  constructor(private readonly vaults: VaultsService) {}

  @Post()
  create(@Req() request: AuthenticatedRequest, @Body() dto: CreateVaultDto) {
    return this.vaults.createVault(request.userID, dto);
  }

  @Get()
  list(@Req() request: AuthenticatedRequest) {
    return this.vaults.listVaults(request.userID);
  }

  @Post(':vaultID/changes')
  appendChange(@Req() request: AuthenticatedRequest, @Param('vaultID') vaultID: string, @Body() dto: AppendChangeDto) {
    return this.vaults.appendChange(request.userID, vaultID, dto);
  }

  @Get(':vaultID/changes')
  listChanges(@Req() request: AuthenticatedRequest, @Param('vaultID') vaultID: string, @Query() query: ListChangesQueryDto) {
    return this.vaults.listChanges(request.userID, vaultID, query.after);
  }
}
