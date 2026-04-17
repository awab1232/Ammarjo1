/** When 1, cross-domain boundary violations throw at runtime (instrumentation). */
export function isArchitectureStrictMode(): boolean {
  return process.env.ARCHITECTURE_STRICT_MODE?.trim() === '1';
}
