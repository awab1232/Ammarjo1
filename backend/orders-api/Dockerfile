# BUILD
FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# RUN
FROM node:18-alpine

WORKDIR /app

COPY --from=builder /app/dist ./dist
COPY package*.json ./
COPY docker-entrypoint.sh ./
COPY scripts/apply-all-sql.cjs ./scripts/
COPY sql/migrations ./sql/migrations

RUN chmod +x docker-entrypoint.sh \
  && npm ci --omit=dev

# Default for containers; Railway dashboard vars override this if set.
ENV NODE_ENV=production

EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["npm", "run", "start:prod"]
