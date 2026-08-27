# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /build
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY . .
RUN npm run build || true

# Stage 2: Runtime
FROM node:20-alpine

# Non-root user (OWASP requirement)
RUN addgroup -g 1000 app && adduser -D -u 1000 -G app app

WORKDIR /app
RUN chown -R app:app /app

# Copy only what you need from builder
COPY --from=builder --chown=app:app /build/node_modules ./node_modules
COPY --from=builder --chown=app:app /build/dist ./dist
COPY --from=builder --chown=app:app /build/package*.json ./

# Switch to non-root
USER app

# Health check for ECS/ACS
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

EXPOSE 3000

CMD ["node", "dist/index.js"]
