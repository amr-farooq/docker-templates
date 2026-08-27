# OWASP-Hardened Docker Template — Quick Reference

## What Each Section Does

### **Stage 1: Builder**
```dockerfile
FROM node:20-alpine AS builder
```
- ✅ **Why multi-stage?** Separates build tools from runtime; final image excludes compiler, tests, source maps
- ✅ **Why alpine?** ~5MB base vs 300MB debian; 90% smaller attack surface
- ✅ **Why specific version (20)?** Prevents unexpected breaking changes from "latest"

```dockerfile
RUN addgroup -g 1000 builder && adduser -D -u 1000 -G builder builder
```
- ✅ **Non-root user in build phase** prevents compromised build process from modifying host
- ✅ **UID 1000** standard non-root UID (0 = root, dangerous)

```dockerfile
COPY package*.json ./
RUN npm ci --only=production
```
- ✅ **Layer caching**: Dependencies cached separately; only rebuilds if package.json changes
- ✅ **npm ci vs npm install**: CI = clean, reproducible installs; enforces exact versions
- ✅ **--only=production**: Excludes devDependencies (testing, linting, build tools)
- ✅ **npm cache clean**: Removes 400MB of cached packages

---

### **Stage 2: Runtime**
```dockerfile
FROM node:20-alpine
```
- ✅ **Fresh image**: No build tools, no temporary files, no previous layers
- ✅ **Minimal base**: Only runtime dependencies (Node.js binary, libc)

```dockerfile
RUN addgroup -g 1000 appuser && adduser -D -u 1000 -G appuser appuser
USER appuser
```
- ✅ **CIS 4.2 Control**: Never run containers as root
- ✅ **Defense in depth**: Even if attacker gains code execution, they're confined to appuser privileges
- ✅ **Can't modify system files**: root-owned files are read-only to appuser

```dockerfile
COPY --from=builder --chown=appuser:appuser /build/node_modules ./node_modules
COPY --from=builder --chown=appuser:appuser /build/dist ./dist
```
- ✅ **Only copies necessary artifacts**: Excludes test files, source maps, .git history
- ✅ **--chown**: Sets correct owner immediately (not after copying)

```dockerfile
RUN apk del --no-cache curl wget git
```
- ✅ **Removes attacker tools**: curl/wget/git could be used to download malware
- ✅ **--no-cache**: Avoids storing package index; saves space

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', ...)"
```
- ✅ **Kubernetes/Docker detection**: Orchestrators can auto-restart hung containers
- ✅ **Prevents zombie processes**: Catches silent failures

```dockerfile
ENV NODE_ENV=production
CMD ["node", "dist/index.js"]
```
- ✅ **Exec form CMD**: Process runs as PID 1 (receives SIGTERM for graceful shutdown)
- ✅ **Shell form would be**: `CMD node dist/index.js` (wraps in /bin/sh, can't receive signals)

---

## OWASP Top 10 Coverage

| OWASP | What It Is | How Docker Solves It |
|-------|-----------|-------------------|
| A01: Broken Access Control | Attackers modify data without authorization | Non-root user + read-only filesystem |
| A02: Cryptographic Failures | Secrets exposed in images | Multi-stage build excludes .env files |
| A03: Injection | SQL/command injection | Minimal image = fewer injectable tools |
| A06: Vulnerable Components | Old, patched dependencies | Frequent rebuilds + vulnerability scanning (Trivy) |
| A08: Data Integrity | Compromised supply chain | Image signing (Cosign) + SBOM (Syft) |

---

## Language-Specific Examples

### **Python**
```dockerfile
# Builder
FROM python:3.12-alpine AS builder
WORKDIR /build
RUN pip install --no-cache-dir -r requirements.txt
RUN pip freeze > requirements.lock.txt

# Runtime
FROM python:3.12-alpine
RUN addgroup -g 1000 appuser && adduser -D -u 1000 appuser
COPY --from=builder --chown=appuser:appuser /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --chown=appuser:appuser . .
USER appuser
CMD ["python", "-u", "main.py"]  # -u = unbuffered output
```

**Key differences:**
- `pip install --no-cache-dir` (equivalent to npm cache clean)
- Python 3.12-alpine (vs 3.12-bullseye/slim)
- `-u` flag ensures logs aren't buffered (critical for Docker logging)

---

### **Go**
```dockerfile
# Builder
FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o app .
# -ldflags: -s strips symbol table, -w removes debug info (smaller binary)

# Runtime
FROM alpine
RUN addgroup -g 1000 appuser && adduser -D -u 1000 appuser
COPY --from=builder --chown=appuser:appuser /build/app /app/
USER appuser
CMD ["/app/app"]
```

**Why this is great:**
- Go compiles to static binary (no runtime dependencies!)
- `CGO_ENABLED=0`: Pure Go (no libc dependencies)
- Can use bare `alpine` image (3MB!)
- `-ldflags` makes binary smaller

---

### **Java**
```dockerfile
# Builder
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline
COPY . .
RUN mvn clean package -DskipTests

# Runtime
FROM eclipse-temurin:21-jre-alpine  # JRE only (no compiler)
RUN addgroup -g 1000 appuser && adduser -D -u 1000 appuser
COPY --from=builder --chown=appuser:appuser /build/target/app.jar /app/
WORKDIR /app
USER appuser
ENV JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0"
CMD ["java", "-jar", "app.jar"]
```

**Critical points:**
- `eclipse-temurin:21-jre-alpine` (JRE only, not JDK)
- Never use `java -jar` in shell form (won't receive SIGTERM)
- `MaxRAMPercentage=75.0`: Use 75% of container limit (prevents OOM)

---

### **Rust**
```dockerfile
# Builder
FROM rust:1.75-alpine AS builder
WORKDIR /build
RUN apk add --no-cache musl-dev
COPY Cargo.lock Cargo.toml ./
RUN cargo build --release
COPY . .
RUN cargo build --release

# Runtime
FROM alpine
RUN addgroup -g 1000 appuser && adduser -D -u 1000 appuser
COPY --from=builder --chown=appuser:appuser /build/target/release/app /app/bin/
USER appuser
CMD ["/app/bin/app"]
```

**Rust advantages:**
- Compiles to static binary (single executable)
- Memory-safe by default (prevents buffer overflows)
- Minimal runtime footprint

---

## Building & Pushing

### **Single-Platform (Fast, local testing)**
```bash
docker build -t myregistry.azurecr.io/myapp:1.0 .
docker push myregistry.azurecr.io/myapp:1.0
```

### **Multi-Platform (ARM + x86, requires buildx)**
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myregistry.azurecr.io/myapp:1.0 \
  --push \
  .
```

---

## Security Scanning

### **Vulnerability Scan (Trivy)**
```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity HIGH,CRITICAL \
  myregistry.azurecr.io/myapp:1.0
```

### **Alternative: Grype**
```bash
grype myregistry.azurecr.io/myapp:1.0
```

### **Software Bill of Materials (SBOM)**
```bash
syft myregistry.azurecr.io/myapp:1.0 -o json > sbom.json
```

### **Sign Image (Cosign)**
```bash
COSIGN_EXPERIMENTAL=1 cosign sign myregistry.azurecr.io/myapp:1.0
COSIGN_EXPERIMENTAL=1 cosign verify myregistry.azurecr.io/myapp:1.0
```

---

## Runtime Security Best Practices

### **Docker Run (Development)**
```bash
docker run --rm \
  --read-only \                          # Immutable filesystem
  --cap-drop=ALL \                       # No Linux capabilities
  --security-opt no-new-privs:true \     # No privilege escalation
  --ulimit nofile=1024:1024 \            # Max file descriptors
  --tmpfs /tmp:size=100m,noexec \        # Temp filesystem, no execute
  -u 1000:1000 \                         # Enforce UID/GID
  myregistry.azurecr.io/myapp:1.0
```

### **Kubernetes Deployment**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
spec:
  containers:
  - name: app
    image: myregistry.azurecr.io/myapp:1.0
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
    livenessProbe:
      httpGet:
        path: /health
        port: 3000
      initialDelaySeconds: 10
      periodSeconds: 30
```

---

## Common Mistakes (What NOT to Do)

❌ **Using latest tag**
```dockerfile
FROM node:latest  # DON'T! Version changes unexpectedly
```
✅ **Use explicit versions**
```dockerfile
FROM node:20.10.0  # Predictable, reproducible
```

---

❌ **Running as root**
```dockerfile
# No USER directive = root
CMD ["node", "app.js"]
```
✅ **Non-root user**
```dockerfile
RUN addgroup -g 1000 appuser && adduser -D -u 1000 appuser
USER appuser
CMD ["node", "app.js"]
```

---

❌ **Bloated base images**
```dockerfile
FROM node:20-bullseye  # 900MB
```
✅ **Minimal base images**
```dockerfile
FROM node:20-alpine  # 150MB
```

---

❌ **Including secrets**
```dockerfile
COPY .env .env.production /app/  # DON'T! Secrets in image
```
✅ **Use build args or volume mounts**
```dockerfile
# At runtime: docker run -e DATABASE_URL=... myapp:1.0
# Or: --secret my-secret=<(cat secret.txt)
```

---

❌ **Shell form CMD (breaks signal handling)**
```dockerfile
CMD node app.js  # Runs under /bin/sh; can't receive SIGTERM
```
✅ **Exec form CMD**
```dockerfile
CMD ["node", "app.js"]  # Direct process; receives signals
```

---

## Checklist Before Pushing

- [ ] Multi-stage build? (builder + runtime)
- [ ] Using alpine or minimal base image?
- [ ] Non-root user created and activated?
- [ ] DevDependencies excluded? (npm ci --only=production)
- [ ] Image scanned with Trivy? (no HIGH/CRITICAL vulns)
- [ ] HEALTHCHECK configured?
- [ ] Using exec form CMD (not shell form)?
- [ ] Unnecessary tools removed? (curl, git, wget)
- [ ] .dockerignore excludes .git, .env, tests?
- [ ] Image size reasonable? (<200MB for most apps)
- [ ] Version pinned (not latest)?
- [ ] Layer caching optimized? (dependencies before code)

---

## Registry Push Commands

### **Azure Container Registry**
```bash
az acr login --name myregistry
docker push myregistry.azurecr.io/myapp:1.0
```

### **AWS ECR**
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456.dkr.ecr.us-east-1.amazonaws.com
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0
```

### **Google Container Registry (GCR)**
```bash
gcloud auth configure-docker
docker push gcr.io/my-project/myapp:1.0
```

### **Docker Hub**
```bash
docker login
docker push myusername/myapp:1.0
```

---

## Key Takeaway

**OWASP-hardened Docker = 3 principles:**

1. **Small** (alpine, multi-stage, remove tools)
2. **Secure** (non-root, drop capabilities, read-only FS)
3. **Verifiable** (scan, sign, SBOM)

Use this template → Build with `build-and-push.sh` → Scan with Trivy → Push confidently.
