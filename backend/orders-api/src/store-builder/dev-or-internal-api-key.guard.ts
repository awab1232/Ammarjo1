import { type CanActivate, type ExecutionContext, Injectable } from '@nestjs/common';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';

/** Requires valid internal API key in all environments. */
@Injectable()
export class DevOrInternalApiKeyGuard implements CanActivate {
  constructor(private readonly internalApiKey: InternalApiKeyGuard) {}

  canActivate(context: ExecutionContext): boolean {
    return this.internalApiKey.canActivate(context);
  }
}
