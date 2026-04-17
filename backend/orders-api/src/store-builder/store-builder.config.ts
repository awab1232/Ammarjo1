export function isHybridStoreBuilderEnabled(): boolean {
  return process.env.ENABLE_HYBRID_STORE_BUILDER?.trim() === 'true';
}

