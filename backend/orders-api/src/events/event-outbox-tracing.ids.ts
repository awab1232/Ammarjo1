import { createHash } from 'node:crypto';

/** Normalize stored trace_id to 32 lowercase hex chars (OTel trace id). */
export function normalizeOtelTraceId(raw: string | null | undefined): string | null {
  if (raw == null || raw === '') {
    return null;
  }
  const s = String(raw).replace(/-/g, '').toLowerCase();
  if (/^[0-9a-f]{32}$/.test(s)) {
    return s;
  }
  return createHash('sha256').update(String(raw)).digest('hex').slice(0, 32);
}

export function deriveSpanIdHex(seed: string): string {
  return createHash('sha256').update(seed).digest('hex').slice(0, 16);
}

export function spanChainForRow(traceIdHex: string, eventId: string): {
  emit: string;
  claim: string;
  handler: string;
  dlq: string;
} {
  const tid = traceIdHex;
  const eid = eventId;
  return {
    emit: deriveSpanIdHex(`${tid}|${eid}|emit`),
    claim: deriveSpanIdHex(`${tid}|${eid}|claim`),
    handler: deriveSpanIdHex(`${tid}|${eid}|handler`),
    dlq: deriveSpanIdHex(`${tid}|${eid}|dlq`),
  };
}

/** W3C traceparent version 00. */
export function traceparentV00(traceId32Hex: string, spanId16Hex: string, sampled = true): string {
  return `00-${traceId32Hex}-${spanId16Hex}-${sampled ? '01' : '00'}`;
}

export function hexToOtlpBase64(hex: string): string {
  return Buffer.from(hex, 'hex').toString('base64');
}
