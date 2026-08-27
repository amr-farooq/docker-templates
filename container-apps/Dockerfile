# ============================================================================
# PRODUCTION DOCKERFILE - OWASP HARDENED
# ============================================================================
# Multi-stage build: Minimal final image, non-root user, security best practices
# Suitable for Node.js, Python, Go, Java - adjust base image and build commands

# Stage 1: Builder
FROM node:20-alpine AS builder

# Security: Create non-root user for build phase
RUN addgroup -g 1000 builder && adduser -D -u 1000 -G builder builder

WORKDIR /build
RUN chown -R builder:builder /build

USER builder

# Copy dependency manifests (enables Docker layer caching)
COPY --chown=builder:builder package*.json ./

# Install production dependencies only (no devDependencies)
RUN npm ci --only=production && npm cache clean --force

# Copy application source
COPY --chown=builder:builder . .

# Build application
RUN npm run build || true

# ============================================================================
# Stage 2: Runtime (Minimal Production Image)
# ============================================================================
FROM node:20-alpine

# METADATA - Required for supply chain security, auditing, and provenance
LABEL maintainer="your-team@company.com"
LABEL version="1.0.0"
LABEL description="Production microservice"
LABEL org.opencontainers.image.source="https://github.com/your-org/your-repo"
LABEL org.opencontainers.image.documentation="https://docs.yourcompany.com/myapp"
LABEL org.opencontainers.image.authors="DevOps Team"
LABEL security.scan="enabled"
LABEL security.signed="false"

# Security: Create non-root user (CIS 4.2 Control)
RUN addgroup -g 1000 appuser && adduser -D -u 1000 -G appuser appuser

# Security: Create app directory with restricted permissions
WORKDIR /app
RUN chmod 755 /app && chown -R appuser:appuser /app

# Copy only necessary artifacts from builder (no dev tools, tests, or source maps)
COPY --from=builder --chown=appuser:appuser /build/node_modules ./node_modules
COPY --from=builder --chown=appuser:appuser /build/dist ./dist
COPY --from=builder --chown=appuser:appuser /build/package*.json ./

# Security: Remove unnecessary packages (reduces attack surface)
RUN apk del --no-cache curl wget git \
    && rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

# Security: Switch to non-root user BEFORE exposing service
USER appuser

# Expose port (informational only)
EXPOSE 3000

# Health check for orchestrators (ECS, ACS)
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Environment settings
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=512"

# Graceful shutdown signal
STOPSIGNAL SIGTERM

# Run application (exec form ensures proper signal handling)
CMD ["node", "dist/index.js"]
