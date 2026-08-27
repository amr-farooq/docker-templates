# Docker Templates — Build, Deploy, Secure

A collection of Docker deployment templates and CI/CD workflows for containerizing applications and deploying them to Azure, AWS, and Kubernetes with security best practices.

Unsigned images never reach production. Deployment requires approval. Every step is audited.

---

## Folder Structure

### 📦 **`simple/`** — Manual Build & Deploy
Straightforward Docker commands and deployment examples for getting started quickly.

**What's inside:**
- Basic multi-stage Dockerfile
- Build and push commands for Azure ACR/AWS ECR
- Deployment instructions for Azure Container Instances (ACI) and AWS ECS
- Troubleshooting guide and health check setup

**Best for:**
- Learning Docker basics
- One-off deployments
- Local testing before automation

**Quick start:**
```bash
# Build and push to Azure
docker build -t myregistry.azurecr.io/myapp:1.0 .
docker push myregistry.azurecr.io/myapp:1.0

# Deploy to ACS
az container create --resource-group mygroup --name myapp-instance --image myregistry.azurecr.io/myapp:1.0
```

See [`simple/README.md`](simple/README.md) for full instructions.

---

### 🚀 **`container-apps/`** — Automated CI/CD with GitHub Actions
Production-ready GitHub Actions pipelines that automate builds, security scanning, and deployment.

**What's inside:**
- **Pipeline 1** (Auto on push): Builds image → Scans vulnerabilities (Trivy) → Generates SBOM (Syft) → Signs image (Cosign) → Pushes to internal registry
- **Pipeline 2** (Manual deployment): Validates artifacts → Pushes to production (ACR/ECR) → Records deployment
- Secret management and environment configuration
- Support for both Azure and AWS

**Key features:**
- ✅ Automatic builds on every push
- ✅ Vulnerability scanning and reporting
- ✅ Software Bill of Materials (SBOM) generation
- ✅ Image signing for supply chain security
- ✅ Manual approval gate before production deployment
- ✅ Full audit trail

**Quick start:**
```bash
# Copy workflows to your repo
mkdir -p .github/workflows
cp container-apps/pipeline1-build.yml .github/workflows/
cp container-apps/pipeline2-deploy.yml .github/workflows/

# Configure secrets (see GITHUB-ACTIONS-SETUP.md)
gh secret set AZURE_CLIENT_ID --body "..."

# Push and watch GitHub Actions → Actions tab
git push origin main
```

See [`container-apps/GITHUB-ACTIONS-QUICKSTART.md`](container-apps/GITHUB-ACTIONS-QUICKSTART.md) for setup guide.

---

### 🛡️ **`kubernetes/`** — OWASP-Hardened Containers
Security-focused Docker templates and best practices aligned with OWASP compliance.

**What's inside:**
- OWASP-hardened Dockerfile template (multi-stage, minimal base image, non-root user)
- Language-specific examples (Node.js, Python, Go, Java, Rust)
- Security checklist and common mistakes
- `build-and-push.sh` script for building and scanning images
- `docker-compose.secure.yml` for local testing with security constraints
- Implementation checklist for production deployments
- Kubernetes deployment manifests with security contexts

**Key hardening practices:**
- 🔒 Non-root user execution
- 🔒 Multi-stage builds to minimize image size
- 🔒 Alpine base images (~5MB vs 300MB for Debian)
- 🔒 Dropped Linux capabilities
- 🔒 Read-only root filesystem
- 🔒 Vulnerability scanning (Trivy)
- 🔒 Image signing and verification

**Quick start:**
```bash
# Build with hardening and scan
cd kubernetes
./build-and-push.sh --registry myregistry.azurecr.io --image myapp --tag 1.0

# Test locally with security constraints
docker-compose -f docker-compose.secure.yml up

# Deploy to Kubernetes
kubectl apply -f deployment.yaml
```

See [`kubernetes/OWASP-DOCKER-GUIDE.md`](kubernetes/OWASP-DOCKER-GUIDE.md) for full security guide.

---

## How They Work Together

```
┌─────────────────────────────────────────────────────────────┐
│  Start with `kubernetes/` → OWASP-hardened Dockerfile       │
│                                                              │
│  For CI/CD automation → Use `container-apps/` GitHub Actions│
│    - Builds from your hardened Dockerfile                  │
│    - Scans for vulnerabilities                             │
│    - Signs and pushes to registry                          │
│                                                              │
│  For manual deployments → Reference `simple/` commands     │
│    - Deploy to ACS/ECS/Kubernetes                          │
│    - Configure environment variables                       │
│    - Manage health checks                                  │
└─────────────────────────────────────────────────────────────┘
```

**Typical workflow:**
1. Write your app and hardened Dockerfile (`kubernetes/` template)
2. Push to GitHub → GitHub Actions runs (`container-apps/` pipelines)
3. Pipelines scan, sign, and push to registry
4. Deploy to production (`simple/` or `container-apps/` deployment step)

---

## Key Concepts

### **Multi-Stage Builds**
Separate build and runtime stages to reduce final image size:
- **Builder stage**: Compiles code, installs dev dependencies
- **Runtime stage**: Only includes compiled code and production dependencies
- **Result**: ~150MB vs ~900MB (6x smaller)

### **Vulnerability Scanning**
Automated security checks using Trivy:
- Finds known CVEs in base image and dependencies
- Blocks deployment if CRITICAL vulnerabilities found
- Generates reports for audit trails

### **Image Signing**
Sign images with Cosign for supply chain security:
- Verifies image hasn't been tampered with
- Proves who built and pushed the image
- Required by production security policies

### **Kubernetes Security Context**
Deploy securely to Kubernetes:
- Run as non-root user
- Drop all Linux capabilities
- Use read-only root filesystem
- Set resource limits

---

## Common Tasks

### Build a Docker image locally
```bash
docker build -t myregistry.azurecr.io/myapp:1.0 .
```

### Scan image for vulnerabilities
```bash
docker run --rm aquasec/trivy image myregistry.azurecr.io/myapp:1.0
```

### Push to Azure Container Registry
```bash
az acr login --name myregistry
docker push myregistry.azurecr.io/myapp:1.0
```

### Push to AWS ECR
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456.dkr.ecr.us-east-1.amazonaws.com
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0
```

### Deploy to Kubernetes
```bash
kubectl apply -f kubernetes/deployment.yaml
```

---

## Security Best Practices

✅ **Always:**
- Use multi-stage builds to minimize image size
- Build from Alpine or minimal base images
- Run containers as non-root user
- Scan images for vulnerabilities before pushing
- Sign images for production deployments
- Use explicit version tags (never `latest`)
- Drop unnecessary Linux capabilities

❌ **Never:**
- Run containers as root
- Include secrets in Dockerfile (`RUN echo $SECRET`)
- Use `latest` tag in production
- Deploy unscanned images
- Use overly permissive base images (Debian, Ubuntu)

---

## Resources

- **[Docker Security Best Practices](https://docs.docker.com/engine/security/)**
- **[OWASP Docker Security](https://owasp.org/)**
- **[Trivy Vulnerability Scanner](https://github.com/aquasecurity/trivy)**
- **[Cosign Image Signing](https://docs.sigstore.dev/)**
- **[Kubernetes Security](https://kubernetes.io/docs/concepts/security/)**

---

## Next Steps

1. **Choose your approach:**
   - Learning? Start with `simple/README.md`
   - CI/CD automation? Follow `container-apps/GITHUB-ACTIONS-QUICKSTART.md`
   - Production security? Use `kubernetes/OWASP-DOCKER-GUIDE.md`

2. **Adapt templates to your app** (language, framework, dependencies)

3. **Test locally** before pushing to registry

4. **Set up GitHub Actions** for automated builds

5. **Deploy confidently** with scanned, signed images
