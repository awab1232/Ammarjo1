export function isDbReadRoutingEnabled(): boolean {
  return process.env.DB_READ_ROUTING_ENABLED?.trim() === '1';
}

export function databaseReadReplicaUrl(): string | undefined {
  const u =
    process.env.DATABASE_READ_REPLICA_URL?.trim() ||
    process.env.ORDERS_DATABASE_READ_REPLICA_URL?.trim();
  return u || undefined;
}
