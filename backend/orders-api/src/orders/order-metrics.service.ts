import { Injectable } from '@nestjs/common';

@Injectable()
export class OrderMetricsService {
  private totalOrders = 0;
  private failedValidations = 0;
  private errorsLogged = 0;
  private writesBackendPayload = 0;
  private writesFirebasePayload = 0;

  recordOrderCreated(validationOk: boolean): void {
    this.totalOrders += 1;
    if (!validationOk) {
      this.failedValidations += 1;
    }
  }

  recordError(): void {
    this.errorsLogged += 1;
  }

  recordWritePayloadSource(writeSource: 'backend' | 'firebase'): void {
    if (writeSource === 'backend') {
      this.writesBackendPayload += 1;
    } else {
      this.writesFirebasePayload += 1;
    }
  }

  getSnapshot(): {
    totalOrders: number;
    failedValidations: number;
    successRate: number;
    errorsLogged: number;
    writeSource: { backend: number; firebase: number };
  } {
    const total = this.totalOrders;
    const failed = this.failedValidations;
    const successRate = total === 0 ? 1 : (total - failed) / total;
    return {
      totalOrders: total,
      failedValidations: failed,
      successRate: Math.round(successRate * 10000) / 10000,
      errorsLogged: this.errorsLogged,
      writeSource: {
        backend: this.writesBackendPayload,
        firebase: this.writesFirebasePayload,
      },
    };
  }
}
