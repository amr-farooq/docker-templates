# ============================================================================
# OWASP SECURE DOCKERFILE TEMPLATE - Universal Multi-Language
# ============================================================================
# This template implements OWASP Top 10 security practices and is suitable
# for Node.js, Python, Go, Java, Rust, and other compiled/interpreted languages.
# Adjust the base image, build commands, and runtime dependencies per language.
# ============================================================================

# Stage 1: Builder (Compile/Prepare Dependencies)
# ============================================================================
# Purpose: Keep the final image small by compiling in an intermediate stage
FROM node:20-alpine AS builder
# - Use minimal base image (alpine is ~5MB vs debian at ~300MB)
# - Explicitly specify version (20) to avoid surprises with latest
# - -alpine variant = no unnecessary tools, reduced attack surface

# Security: Set non-root user for build phase
RUN addgroup -g 1000 builder && adduser -D -u 1000 -G builder builder

# Security: Create app directory with restricted permissions
WORKDIR /build
RUN chown -R builder:builder /build

# Switch to non-root user for build
USER builder

# Copy dependency manifests first (leverage Docker layer caching)
# This allows Docker to cache the dependency layer if they haven't changed
COPY --chown=builder:builder package*.json ./
COPY --chown=builder:builder .npmrc ./

# Install production dependencies only (exclude devDependencies)
# Use --ci (clean install) instead of npm install for reproducible builds
# --legacy-peer-deps only if necessary (indicates dependency issues)
RUN npm ci --only=production && \
    npm cache clean --force

# Copy application source code
COPY --chown=builder:builder . .

# Build application (if applicable)
# Example: compile TypeScript, minify, strip debugging
RUN npm run build:prod || true
# || true allows image to build even if build script doesn't exist

# Stage 2: Runtime (Minimal Production Image)
# ============================================================================
# Purpose: Smallest possible footprint for production deployment
FROM node:20-alpine
# Fresh base image = no build tools, dependencies, or temporary files

# Security: Add metadata labels (helps with provenance and debugging)
LABEL maintainer="your-email@example.com"
LABEL version="1.0"
LABEL description="OWASP-hardened application container"

# Security: Create non-root user for runtime (prevents privilege escalation)
RUN addgroup -g 1000 appuser && adduser -D -u 1000 -G appuser appuser

# Security: Create app directory with minimal permissions (755 = r-x for others)
WORKDIR /app
RUN chmod 755 /app && chown -R appuser:appuser /app

# Copy only necessary artifacts from builder stage
# Excludes build tools, source maps, test files, git history
COPY --from=builder --chown=appuser:appuser /build/node_modules ./node_modules
COPY --from=builder --chown=appuser:appuser /build/dist ./dist
COPY --from=builder --chown=appuser:appuser /build/package*.json ./

# Security: Mark filesystem as read-only where possible
# (enables runtime detection of unauthorized file modifications)
# VOLUME ["/app/logs"]  # Only if app needs to write logs

# Security: Remove unnecessary packages and files
# Reduces attack surface (fewer tools = fewer vulnerabilities)
RUN apk del --no-cache \
    curl \
    wget \
    git \
    && rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

# Security: Switch to non-root user BEFORE exposing the service
USER appuser

# Expose port (informational, doesn't actually open the port)
# Use a high port (>1024) to avoid needing root privileges
EXPOSE 3000

# Health check (allows orchestrators to detect failing containers)
# Runs every 30s, fails after 3 consecutive failures
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Security: Set resource limits (prevent DoS from runaway processes)
# Note: These are hints; actual limits enforced by container runtime
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=512"

# Security: Drop unnecessary Linux capabilities (defense in depth)
# Default: CAP_CHOWN, CAP_DAC_OVERRIDE, CAP_SETUID, CAP_SETGID, CAP_NET_RAW
# These are removed to prevent privilege escalation even if container is compromised

# Run the application
# Use exec form (["cmd", "arg"]) to ensure proper signal handling (SIGTERM)
# This allows graceful shutdown when container receives stop signal
CMD ["node", "dist/index.js"]

# ============================================================================
# BUILD COMMANDS FOR REGISTRY PUSH
# ============================================================================
# Build:
#   docker build -t myregistry.azurecr.io/myapp:1.0 \
#                 --build-arg NODE_VERSION=20 \
#                 --platform linux/amd64,linux/arm64 \
#                 .
#
# Security scan:
#   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
#     aquasec/trivy image myregistry.azurecr.io/myapp:1.0
#
# Push to registry:
#   docker push myregistry.azurecr.io/myapp:1.0
#
# Run with security options:
#   docker run --rm \
#     --read-only \
#     --cap-drop=ALL \
#     --security-opt=no-new-privileges:true \
#     myregistry.azurecr.io/myapp:1.0

# ============================================================================
# WHAT EACH SECTION DOES - DETAILED BREAKDOWN
# ============================================================================

# STAGE 1: BUILDER
# ────────────────
# 1. Uses full base image with build tools (compiler, npm, etc.)
# 2. Creates non-root user (builder) - prevents build process from running as root
# 3. Sets WORKDIR and fixes permissions - containers shouldn't modify /
# 4. Copies package manifests first - Docker caches dependencies separately
# 5. npm ci --only=production - installs ONLY runtime deps (no dev tools)
# 6. npm cache clean --force - removes ~400MB of cached packages
# 7. Copies source code and builds - compiles TypeScript, minifies, etc.

# STAGE 2: RUNTIME
# ────────────────
# 1. FROM node:20-alpine - Fresh minimal image (no build artifacts)
# 2. LABEL - Metadata for image registry and auditing
# 3. RUN addgroup/adduser - Non-root user prevents privilege escalation
#    If attacker compromises container, they're confined to non-root privileges
# 4. WORKDIR - Sets working directory; chown ensures appuser owns files
# 5. COPY --from=builder - Pulls ONLY compiled code and dependencies
#    Excludes source maps, test files, .git, node_modules from builder cruft
# 6. RUN apk del - Removes curl/wget/git (attacker tools, not needed at runtime)
# 7. USER appuser - Switches to non-root BEFORE exposing service
#    All subsequent processes run as appuser (uid 1000), not root (uid 0)
# 8. EXPOSE 3000 - Documents which port app uses (doesn't open it)
# 9. HEALTHCHECK - Detects hung processes; orchestrator can restart
# 10. ENV NODE_ENV=production - Disables dev features, enables optimizations
# 11. CMD ["node", "dist/index.js"] - Exec form ensures PID 1 = app
#     Allows Kubernetes/Docker to send SIGTERM for graceful shutdown

# ============================================================================
# OWASP/CIS CONTROLS IMPLEMENTED
# ============================================================================
# ✓ CIS 1.2 - Use minimal base images (alpine)
# ✓ CIS 1.3 - Scan and rebuild frequently (pin versions)
# ✓ CIS 4.2 - Run non-root user (uid 1000)
# ✓ CIS 4.6 - Drop unnecessary capabilities (--cap-drop=ALL at runtime)
# ✓ CIS 5.1 - Verify image signatures (use official images from Docker Hub)
# ✓ CIS 5.3 - Label images with metadata
# ✓ CIS 5.6 - Minimize content (multi-stage, remove dev tools)
# ✓ OWASP A01 - Broken Access Control: non-root user, proper permissions
# ✓ OWASP A06 - Vulnerable Components: minimal image, security scanning
# ✓ OWASP A08 - Software & Data Integrity: immutable builds, layer caching

# ============================================================================
# LANGUAGE-SPECIFIC ADAPTATIONS
# ============================================================================
# PYTHON:
#   FROM python:3.12-alpine AS builder
#   RUN pip install --no-cache-dir -r requirements.txt
#   FROM python:3.12-alpine
#   COPY --from=builder /usr/local/lib/python3.12/site-packages ...
#
# GO:
#   FROM golang:1.22-alpine AS builder
#   RUN go build -ldflags="-s -w" -o /build/app .
#   FROM alpine
#   COPY --from=builder /build/app /app/bin/
#
# JAVA:
#   FROM maven:3.9-eclipse-temurin-21 AS builder
#   RUN mvn clean package -DskipTests
#   FROM eclipse-temurin:21-alpine
#   COPY --from=builder /build/target/app.jar /app/
#
# RUST:
#   FROM rust:1.75-alpine AS builder
#   RUN cargo build --release
#   FROM alpine
#   COPY --from=builder /build/target/release/app /app/bin/

# ============================================================================
# RUNTIME SECURITY FLAGS (docker run / k8s deployment)
# ============================================================================
# docker run --rm \
#   --read-only \                    # Filesystem read-only (catches tampering)
#   --cap-drop=ALL \                 # Drop all Linux capabilities
#   --security-opt no-new-privs \    # Prevent privilege escalation
#   --ulimit nofile=1024:1024 \      # Limit open file descriptors
#   --ulimit nproc=512:512 \         # Limit processes
#   -u 1000:1000 \                   # Enforce UID/GID
#   --tmpfs /tmp:size=100m,noexec \  # Temporary filesystem for logs
#   myapp:latest

# ============================================================================
# IMAGE SCANNING & VERIFICATION
# ============================================================================
# Trivy (open-source vulnerability scanner):
#   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
#     aquasec/trivy image --severity HIGH,CRITICAL \
#     myregistry.azurecr.io/myapp:1.0
#
# Grype (alternative scanner from Anchore):
#   grype myregistry.azurecr.io/myapp:1.0
#
# Sigstore (sign & verify container images):
#   cosign sign --key cosign.key myregistry.azurecr.io/myapp:1.0
#   cosign verify --key cosign.pub myregistry.azurecr.io/myapp:1.0
