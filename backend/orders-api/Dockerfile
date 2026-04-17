# NestJS orders-api — production image for Railway / Docker.
# Multi-stage: compile TypeScript in `builder`, ship a slim runtime.

# -------- builder --------
FROM node:18-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY nest-cli.json tsconfig.json ./
COPY src ./src
COPY scripts ./scripts
RUN npm run build && rm -rf node_modules

# -------- runner ---------
FROM node:18-alpine AS runner
WORKDIR /app

# UTF-8 locale so Arabic flows cleanly through logs, libc, and libpq.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NODE_ENV=production \
    PORT=3000 \
    PGCLIENTENCODING=UTF8

# psql is required by docker-entrypoint.sh to run migrations on boot.
RUN apk add --no-cache postgresql-client

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/dist ./dist
COPY sql/migrations /sql/migrations
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && chown -R node:node /app

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --quiet --spider --timeout=3 "http://127.0.0.1:${PORT}/health" || exit 1

CMD ["node", "dist/main.js"]
