/**
 * Use when logging caught errors from DB/network clients — avoids dumping full Error objects
 * that might include connection metadata. Never log env vars or raw connection strings.
 */
export function safeErrorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
