export function isDbReadRoutingEnabled(): boolean {
  return process.env.DB_READ_ROUTING_ENABLED?.trim() === '1';
}

export function databaseReadReplicaUrl(): string | undefined {
  const u = process.env.DATABASE_URL?.trim();
  return u != null && u !== '' ? u : undefined;
}
