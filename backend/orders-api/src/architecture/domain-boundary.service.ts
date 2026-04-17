import { Injectable, Logger } from '@nestjs/common';
import { isArchitectureStrictMode } from './architecture.config';
import type { DomainKey } from './domain-id';

export interface BoundaryViolation {
  rule: string;
  from?: DomainKey;
  to?: DomainKey;
  detail: string;
}

/**
 * Records cross-domain boundary violations. In strict mode, throws so CI or tests can fail fast.
 */
@Injectable()
export class DomainBoundaryService {
  private readonly logger = new Logger(DomainBoundaryService.name);

  recordViolation(v: BoundaryViolation): void {
    const msg = `[architecture] ${v.rule}${v.from && v.to ? ` (${v.from} → ${v.to})` : ''}: ${v.detail}`;
    if (isArchitectureStrictMode()) {
      throw new Error(msg);
    }
    this.logger.warn(msg);
  }
}
