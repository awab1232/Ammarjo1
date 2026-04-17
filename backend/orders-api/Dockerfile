# syntax=docker/dockerfile:1
# Multi-stage build for the NestJS orders-api. Compiles TypeScript in the
# builder stage and produces a minimal production runtime image.
#
# Designed to run on:
#   * docker-compose (local / staging)
#   * Railway.app (auto-detected Dockerfile deploy)
#   * Fly.io / Render / Cloud Run (any OCI-compatible runtime)

# -------- builder --------
FROM node:20-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY nest-cli.json tsconfig.json ./
COPY src ./src
RUN npm run build && rm -rf node_modules

# -------- runner ---------
FROM node:20-alpine AS runner
WORKDIR /app

# UTF-8 locale for Arabic correctness in logs, error messages, and any
# libc/iconv conversion inside the container.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NODE_ENV=production \
    PORT=3000 \
    # Forces libpq clients to transcode to UTF8 regardless of server default.
    PGCLIENTENCODING=UTF8

# psql is required by docker-entrypoint.sh to apply migrations on boot.
# tini is a minimal init (PID 1) so SIGTERM is propagated cleanly by Railway.
RUN apk add --no-cache postgresql-client tini

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/dist ./dist
COPY sql/migrations /sql/migrations
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && chown -R node:node /app

USER node

EXPOSE 3000

# Platform-agnostic healthcheck — Railway honors the HEALTHCHECK directive
# and will route traffic only after the process reports healthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --quiet --spider --timeout=3 \
      "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["npm", "run", "start:prod"]
