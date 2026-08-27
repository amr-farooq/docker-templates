# OWASP Docker Template — Implementation Checklist

## 📋 Quick Start (5 minutes)

### 1. Copy Files to Your Project
```bash
# Copy the universal Dockerfile template
cp Dockerfile Dockerfile

# Copy the ignore file
cp .dockerignore .dockerignore

# Copy the build script (requires chmod +x)
cp build-and-push.sh build-and-push.sh
chmod +x build-and-push.sh

# Optional: Copy docker-compose for local testing
cp docker-compose.secure.yml docker-compose.yml
```

### 2. Customize for Your Language

**Node.js (Ready to go)**
- No changes needed; template is Node.js-first

**Python**
```dockerfile
# Replace builder FROM
FROM python:3.12-alpine AS builder

# Replace runtime FROM
FROM python:3.12-alpine

# Replace install
RUN pip install --no-cache-dir -r requirements.txt

# Replace CMD
CMD ["python", "-u", "main.py"]  # -u = unbuffered
```

**Go**
```dockerfile
FROM golang:1.22-alpine AS builder
# ... (see OWASP-DOCKER-GUIDE.md for full example)
```

**Java**
```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS builder
# ... (see OWASP-DOCKER-GUIDE.md for full example)
```

### 3. Build & Test Locally
```bash
# Make script executable
chmod +x build-and-push.sh

# Build image
./build-and-push.sh myapp 1.0.0 myregistry.azurecr.io

# OR build manually
docker build -t myapp:latest .

# Test the image
docker run --rm -it myapp:latest

# Verify runs as non-root
docker run --rm myapp:latest whoami  # Should output: appuser
```

### 4. Scan for Vulnerabilities
```bash
# Install Trivy (if not already installed)
# macOS: brew install aquasecurity/trivy/trivy
# Linux: wget https://github.com/aquasecurity/trivy/releases/download/v0.48.0/trivy_0.48.0_Linux-64bit.tar.gz

# Scan image
trivy image --severity HIGH,CRITICAL myapp:latest

# Fix any HIGH/CRITICAL issues before proceeding
```

### 5. Push to Registry
```bash
# Azure Container Registry
az acr login --name myregistry
docker push myregistry.azurecr.io/myapp:1.0.0

# AWS ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456.dkr.ecr.us-east-1.amazonaws.com
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0.0

# Google GCR
gcloud auth configure-docker
docker push gcr.io/my-project/myapp:1.0.0

# Docker Hub
docker login
docker push myusername/myapp:1.0.0
```

---

## ✅ Pre-Build Checklist

- [ ] Dockerfile customized for your language?
- [ ] .dockerignore excludes .env, .git, node_modules, test files?
- [ ] Base image version pinned (not "latest")?
- [ ] Non-root user created in both builder and runtime?
- [ ] Dependencies isolated from source code?
- [ ] Multi-stage build implemented?
- [ ] Build artifacts (dist/, __pycache__) excluded from runtime?
- [ ] HEALTHCHECK endpoint configured?
- [ ] PORT documented in EXPOSE?

---

## ✅ Build Checklist

```bash
# Run these commands before pushing
docker build -t myapp:1.0.0 .
docker images myapp:1.0.0  # Check size
docker history myapp:1.0.0 | head -20  # Inspect layers
```

- [ ] Image size < 200MB? (adjust if > 500MB)
- [ ] Runs as non-root user? (`docker run myapp:1.0.0 whoami` = appuser)
- [ ] HEALTHCHECK working? (`docker inspect myapp:1.0.0 | grep -i health`)
- [ ] No secrets in image? (`docker run myapp:1.0.0 env | grep -i secret`)

---

## ✅ Security Scanning Checklist

```bash
# 1. Vulnerability scan
trivy image --severity HIGH,CRITICAL myapp:1.0.0

# 2. Inspect running user
docker run --rm myapp:1.0.0 id

# 3. Check for debug tools
docker run --rm myapp:1.0.0 which curl wget vim
```

- [ ] No HIGH or CRITICAL vulnerabilities?
- [ ] Running as UID 1000 (non-root)?
- [ ] No curl/wget/git/vim in image?
- [ ] Filesystem truly read-only? (`docker run --read-only myapp:1.0.0`)

---

## ✅ Registry Push Checklist

- [ ] Logged into registry? (`docker login` or `az acr login`)
- [ ] Image tagged correctly? (`docker tag myapp:1.0.0 myregistry.azurecr.io/myapp:1.0.0`)
- [ ] Registry endpoint correct? (check for typos)
- [ ] Image pushed successfully? (`docker pull myregistry.azurecr.io/myapp:1.0.0`)
- [ ] Tag with `latest`? (`docker tag myapp:1.0.0 myregistry.azurecr.io/myapp:latest`)

---

## ✅ Deployment Checklist (Kubernetes)

```yaml
# example deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myregistry.azurecr.io/myapp:1.0.0
        imagePullPolicy: IfNotPresent  # Prefer cached image
        
        # Security context (matches Dockerfile)
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          capabilities:
            drop:
            - ALL
        
        # Resource requests & limits (matches Dockerfile limits)
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Health check (matches Dockerfile HEALTHCHECK)
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
        
        # Volume for logs (if needed)
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: logs
          mountPath: /app/logs
      
      # Volumes
      volumes:
      - name: tmp
        emptyDir: {}
      - name: logs
        emptyDir: {}
```

- [ ] Image pull policy set to `IfNotPresent`?
- [ ] Security context matches Dockerfile?
- [ ] Resource limits set (memory, CPU)?
- [ ] Liveness & readiness probes configured?
- [ ] Replica count > 1 for HA?
- [ ] Image pull secrets configured (if private registry)?

---

## 🔍 Testing Commands

### Verify Image Security
```bash
# Does it run as non-root?
docker run --rm myapp:1.0.0 id
# Expected: uid=1000(appuser) gid=1000(appuser)

# Are we dropping capabilities?
docker run --rm --cap-drop=ALL myapp:1.0.0 /bin/sh
# Should fail with: "container has no capability"

# Is filesystem truly read-only?
docker run --rm --read-only myapp:1.0.0 touch /test
# Should fail with: "Read-only file system"

# Does HEALTHCHECK work?
docker run -d --name test-app myapp:1.0.0
docker inspect test-app | grep -A 5 Health
# Expected: "HealthStatus": "healthy" after a few seconds
docker rm -f test-app
```

### Verify Dependencies
```bash
# Check layer size
docker history myapp:1.0.0 --no-trunc --human

# Inspect image details
docker inspect myapp:1.0.0 | jq '.Config.User, .Config.Env, .Size'

# View entrypoint
docker inspect myapp:1.0.0 | jq '.Config.Entrypoint'
```

### Vulnerability Scan
```bash
# Install Trivy if not present
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Scan with detailed output
trivy image --verbose --severity HIGH,CRITICAL myapp:1.0.0

# Scan and generate JSON report
trivy image --format json --output report.json myapp:1.0.0
```

---

## 📊 Performance Benchmarks

**Healthy Metrics:**

| Metric | Target | Status |
|--------|--------|--------|
| Image size | < 200MB | ✅ |
| Startup time | < 5s | ✅ |
| Non-root user | Yes | ✅ |
| Vulnerabilities (HIGH/CRITICAL) | 0 | ✅ |
| Layers | < 20 | ✅ |
| Build time | < 2min | ✅ |

**Check your image:**
```bash
# Size
docker images myapp:1.0.0 --format "{{.Size}}"

# Layers
docker history myapp:1.0.0 | tail -n +2 | wc -l

# Build time
time docker build -t myapp:1.0.0 .
```

---

## 🚀 Complete Build → Test → Push Workflow

```bash
#!/bin/bash
set -e

APP_NAME="myapp"
VERSION="1.0.0"
REGISTRY="myregistry.azurecr.io"

echo "🔨 Building..."
docker build -t ${REGISTRY}/${APP_NAME}:${VERSION} .

echo "✅ Verifying..."
docker run --rm ${REGISTRY}/${APP_NAME}:${VERSION} whoami

echo "🔍 Scanning..."
trivy image --severity HIGH,CRITICAL ${REGISTRY}/${APP_NAME}:${VERSION}

echo "📤 Pushing..."
docker push ${REGISTRY}/${APP_NAME}:${VERSION}
docker tag ${REGISTRY}/${APP_NAME}:${VERSION} ${REGISTRY}/${APP_NAME}:latest
docker push ${REGISTRY}/${APP_NAME}:latest

echo "✨ Done! Pull with:"
echo "  docker pull ${REGISTRY}/${APP_NAME}:${VERSION}"
```

---

## 📚 Documentation

- **Dockerfile** — Annotated with inline comments; see "What Each Section Does"
- **OWASP-DOCKER-GUIDE.md** — Detailed explanations and language-specific examples
- **docker-compose.secure.yml** — Secure local testing environment
- **build-and-push.sh** — Production build pipeline with vulnerability scanning

---

## ❓ Troubleshooting

### "docker: command not found"
```bash
# Install Docker Desktop (macOS/Windows) or Docker Engine (Linux)
# https://docs.docker.com/engine/install/
```

### "permission denied while trying to connect to Docker daemon"
```bash
# Add your user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker
```

### "base image not found"
```bash
# Ensure Docker can pull from registry
docker pull node:20-alpine

# If behind corporate proxy, configure Docker daemon:
# ~/.docker/config.json or Docker Desktop Settings
```

### "image running as root"
```bash
# Check Dockerfile USER directive
grep "^USER" Dockerfile

# If missing, add after RUN commands:
# USER appuser
```

### "HIGH vulnerabilities found"
```bash
# Update base image version
FROM node:20-alpine  # Update to node:20.10.0 (explicit version)

# Rebuild
docker build --no-cache -t myapp:1.0.0 .

# Rescan
trivy image myapp:1.0.0
```

### "Image size > 500MB"
```bash
# Check layer sizes
docker history myapp:1.0.0 --no-trunc --human | head -20

# Common issues:
# 1. DevDependencies not excluded: npm ci --only=production
# 2. npm cache not cleaned: npm cache clean --force
# 3. Test files included: Update .dockerignore
# 4. Using bloated base image: Switch to alpine variant
```

---

## 🎯 Next Steps

1. **Copy files to your project**
2. **Customize Dockerfile for your language**
3. **Build locally and test**
4. **Scan for vulnerabilities**
5. **Push to registry**
6. **Deploy to Kubernetes/Docker Swarm**
7. **Monitor with your orchestration platform**

**You now have a production-grade, OWASP-hardened container!**

---

## 📖 Further Reading

- **CIS Docker Benchmark**: https://www.cisecurity.org/benchmark/docker
- **OWASP Container Security**: https://cheatsheetseries.owasp.org/cheatsheets/Container_Security_Cheat_Sheet.html
- **Docker Security Best Practices**: https://docs.docker.com/engine/security/
- **Kubernetes Pod Security Standards**: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- **Trivy Scanner**: https://aquasecurity.github.io/trivy/
- **Cosign Image Signing**: https://docs.sigstore.dev/cosign/
