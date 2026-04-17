import { Injectable } from '@nestjs/common';

export type ProductionReadinessInput = {
  dbPrimaryOk: boolean;
  redisEnabled: boolean;
  redisReady: boolean;
  cacheEnabled: boolean;
  cacheHitRatio: number | null;
  outboxEnabled: boolean;
  outboxLag: number | null;
  processingBacklog: number;
  replicaLagSeconds: number | null;
};

export type ProductionReadinessResult = {
  isProductionReady: boolean;
  criticalWarnings: string[];
  systemScore: number;
};

@Injectable()
export class ProductionReadinessService {
  getProductionReadiness(input: ProductionReadinessInput): ProductionReadinessResult {
    const criticalWarnings: string[] = [];
    let score = 100;

    const dlqThreshold = Number(process.env.SLO_DLQ_THRESHOLD || 500);
    const lagThreshold = Number(process.env.SLO_EVENT_LAG_THRESHOLD || 1000);
    const replicaLagThreshold = Number(process.env.SLO_REPLICA_LAG_SECONDS || 30);
    const minCacheHitRatio = Number(process.env.SLO_MIN_CACHE_HIT_RATIO || 0.1);

    if (!input.dbPrimaryOk) {
      criticalWarnings.push('Primary database health check is failing.');
      score -= 40;
    }
    if (input.redisEnabled && !input.redisReady) {
      criticalWarnings.push('Redis is enabled but not ready.');
      score -= 20;
    }
    if (input.outboxEnabled && (input.outboxLag ?? 0) > lagThreshold) {
      criticalWarnings.push(`Event outbox lag is high (${input.outboxLag} > ${lagThreshold}).`);
      score -= 20;
    }
    if (input.processingBacklog > dlqThreshold) {
      criticalWarnings.push(`Event processing/DLQ pressure is high (${input.processingBacklog} > ${dlqThreshold}).`);
      score -= 15;
    }
    if (
      input.replicaLagSeconds != null &&
      input.replicaLagSeconds > replicaLagThreshold
    ) {
      criticalWarnings.push(
        `Database replica lag is high (${input.replicaLagSeconds}s > ${replicaLagThreshold}s).`,
      );
      score -= 10;
    }
    if (
      input.cacheEnabled &&
      input.cacheHitRatio != null &&
      input.cacheHitRatio < minCacheHitRatio
    ) {
      criticalWarnings.push(
        `Cache hit ratio is below target (${input.cacheHitRatio} < ${minCacheHitRatio}).`,
      );
      score -= 5;
    }

    const boundedScore = Math.max(0, Math.min(100, score));
    return {
      isProductionReady: criticalWarnings.length === 0,
      criticalWarnings,
      systemScore: boundedScore,
    };
  }

  evaluate(input: ProductionReadinessInput): ProductionReadinessResult {
    return this.getProductionReadiness(input);
  }

  assertProductionReady(input: ProductionReadinessInput): void {
    const result = this.getProductionReadiness(input);
    if (!result.isProductionReady) {
      throw new Error(
        `SYSTEM NOT PRODUCTION READY | systemScore=${result.systemScore} | criticalWarnings=${result.criticalWarnings.join('; ')}`,
      );
    }
  }
}

