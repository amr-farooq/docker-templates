# Two-Pipeline Deployment Model

## Architecture

```
Developer Machine / CI Pipeline (Git Push)
           ↓
    [PIPELINE 1: BUILD]
    - Build Docker image
    - Scan for vulnerabilities
    - Generate SBOM
    - Create attestation
    - Generate checksums
    - Sign image
    - Push to INTERNAL registry
           ↓
    (Artifacts: trivy-report, sbom, attestation, checksums)
           ↓
    [Approval Window / Deployment Schedule]
           ↓
    [PIPELINE 2: VALIDATE & DEPLOY]
    - Verify signatures
    - Validate checksums
    - Check artifacts
    - Verify no critical vulnerabilities
    - Push to PRODUCTION (ACR/ECR)
           ↓
    [ACS / ECS]
    - Pull from production registry
    - Deploy container
```

## Why Two Pipelines?

1. **Separation of Concerns**
   - Build = Dev responsibility (compile, test, scan)
   - Deploy = Ops responsibility (approve, deploy, audit)

2. **Security Controls**
   - Unsigned images never reach production
   - Deployment requires approval (gated by time/manual check)
   - All decisions are audited (who deployed, when, why)

3. **Audit Trail**
   - Each pipeline creates artifacts
   - Deployment record shows exactly what was deployed
   - Can trace from git commit → image → deployment

## Quick Start

### Setup (one-time)

```bash
# Make scripts executable
chmod +x pipeline1-build.sh
chmod +x pipeline2-validate-deploy.sh

# Set environment variables for Pipeline 2
export ACR_REGISTRY="myregistry.azurecr.io"     # For Azure
# OR
export ECR_REGISTRY="123456.dkr.ecr.us-east-1.amazonaws.com"  # For AWS
```

### Pipeline 1: Build (On Commit or Manually)

```bash
# Run on developer machine or in CI pipeline
./pipeline1-build.sh myapp 1.0.0 registry.internal:5000

# Output:
# ✓ Image built and scanned
# ✓ Signed and pushed to internal registry
# ✓ Artifacts created in ./build-artifacts/
#
# Next: Run Pipeline 2 during deployment window
```

### Pipeline 2: Validate & Deploy (During Deployment Window)

```bash
# Run on deployment infrastructure (gated access)
./pipeline2-validate-deploy.sh myapp 1.0.0 registry.internal:5000 acr
# or for AWS
./pipeline2-validate-deploy.sh myapp 1.0.0 registry.internal:5000 ecr

# Output:
# ✓ Image verified and validated
# ✓ Pushed to production ACR/ECR
# ✓ Deployment record created
# ✓ Ready for ACS/ECS deployment
```

---

## Artifacts Created

### Pipeline 1 (`./build-artifacts/`)

| File | Purpose |
|------|---------|
| `trivy-report-1.0.0.json` | Vulnerability scan results |
| `sbom-1.0.0.json` | Software bill of materials (all dependencies) |
| `attestation-1.0.0.json` | Build metadata (commit, branch, builder, etc.) |
| `checksums-1.0.0.txt` | Image digest and size for verification |

**Use for:**
- Security review before deployment
- Compliance/audit requirements
- Supply chain verification

### Pipeline 2 (`./build-artifacts/`)

| File | Purpose |
|------|---------|
| `deployment-1.0.0.json` | Deployment metadata (when, who, where, status) |

**Use for:**
- Audit trail
- Incident investigation
- Compliance reporting

---

## Security Checks

### Pipeline 1: Build Phase

✓ Image is built with OWASP hardening (non-root, multi-stage, minimal)  
✓ Vulnerabilities scanned (Trivy)  
✓ Image signed (Cosign)  
✓ SBOM generated (Syft)  
✓ Checksums recorded  
✓ Pushed to **internal** registry only  

### Pipeline 2: Deployment Phase

✓ Signature verified (Cosign)  
✓ Checksums validated (image integrity)  
✓ Artifacts checked (trivy, sbom, attestation)  
✓ No critical vulnerabilities allowed  
✓ Pushed to **production** registry (ACR/ECR) only  
✓ Deployment recorded  

---

## Manual/CI/CD Integration

### GitHub Actions (Example for Pipeline 1)

```yaml
name: Build & Push to Internal Registry

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'Dockerfile'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Login to internal registry
        run: docker login -u ${{ secrets.INTERNAL_REGISTRY_USER }} -p ${{ secrets.INTERNAL_REGISTRY_PASS }} registry.internal:5000
      
      - name: Run Pipeline 1
        run: |
          chmod +x pipeline1-build.sh
          ./pipeline1-build.sh myapp ${{ github.sha }} registry.internal:5000
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: build-artifacts
          path: build-artifacts/
```

### GitHub Actions (Example for Pipeline 2)

```yaml
name: Validate & Deploy to Production

on:
  workflow_dispatch:  # Manual trigger (approval gate)
    inputs:
      version:
        description: 'Version to deploy'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: production
      # Requires manual approval in GitHub
    steps:
      - uses: actions/checkout@v3
      
      - name: Download artifacts
        uses: actions/download-artifact@v3
        with:
          name: build-artifacts
          path: build-artifacts/
      
      - name: Setup Azure CLI
        run: az login --service-principal -u ${{ secrets.AZURE_CLIENT_ID }} -p ${{ secrets.AZURE_CLIENT_SECRET }} --tenant ${{ secrets.AZURE_TENANT_ID }}
      
      - name: Run Pipeline 2
        run: |
          chmod +x pipeline2-validate-deploy.sh
          export ACR_REGISTRY="myregistry.azurecr.io"
          ./pipeline2-validate-deploy.sh myapp ${{ github.event.inputs.version }} registry.internal:5000 acr
```

---

## GitLab CI (Example for Pipeline 1)

```yaml
build_and_push:
  stage: build
  script:
    - chmod +x pipeline1-build.sh
    - ./pipeline1-build.sh myapp ${CI_COMMIT_SHORT_SHA} registry.internal:5000
  artifacts:
    paths:
      - build-artifacts/
    expire_in: 30 days
  only:
    - main
```

## GitLab CI (Example for Pipeline 2 - Gated Deployment)

```yaml
deploy_to_production:
  stage: deploy
  script:
    - export ACR_REGISTRY="myregistry.azurecr.io"
    - chmod +x pipeline2-validate-deploy.sh
    - ./pipeline2-validate-deploy.sh myapp ${CI_COMMIT_TAG} registry.internal:5000 acr
  environment:
    name: production
  when: manual  # Requires manual approval
  only:
    - tags
```

---

## Troubleshooting

### Pipeline 1: Build fails

```bash
# Check Docker is running
docker ps

# Check internal registry is accessible
docker login registry.internal:5000

# Check Dockerfile exists
ls -la Dockerfile

# Run with verbose output
bash -x pipeline1-build.sh myapp 1.0.0 registry.internal:5000
```

### Pipeline 2: Validation fails

```bash
# Check artifacts exist from Pipeline 1
ls -la build-artifacts/

# Check you can pull from internal registry
docker pull registry.internal:5000/myapp:1.0.0

# Check authentication with production registry
az acr login --name myregistry  # For Azure
# OR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456.dkr.ecr.us-east-1.amazonaws.com

# Run with verbose output
bash -x pipeline2-validate-deploy.sh myapp 1.0.0 registry.internal:5000 acr
```

### Signature verification fails

```bash
# Make sure Cosign is installed
brew install cosign  # macOS
# or from https://docs.sigstore.dev/cosign/installation/

# For experimental mode (no key needed)
export COSIGN_EXPERIMENTAL=1
cosign verify registry.internal:5000/myapp:1.0.0
```

### Critical vulnerabilities found

```bash
# Review the Trivy report
cat build-artifacts/trivy-report-1.0.0.json | jq '.Results'

# Common fixes:
# 1. Update base image (e.g., node:20-alpine → node:20.10.0-alpine)
# 2. Update dependencies (npm update)
# 3. Remove unnecessary packages (apk del)

# After fixing, re-run Pipeline 1
```

---

## Deployment to ACS/ECS

### Azure ACS

```bash
# After Pipeline 2, deploy with:
az container create \
  --resource-group mygroup \
  --name myapp-prod \
  --image myregistry.azurecr.io/myapp:1.0.0 \
  --registry-login-server myregistry.azurecr.io \
  --registry-username <username> \
  --registry-password <password> \
  --ports 3000 \
  --cpu 1 --memory 1.0

# View logs
az container logs --resource-group mygroup --name myapp-prod --follow
```

### AWS ECS

```bash
# Create task definition (task-definition.json) with image from Pipeline 2
{
  "family": "myapp",
  "containerDefinitions": [
    {
      "name": "myapp",
      "image": "123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0.0",
      "portMappings": [{"containerPort": 3000}]
    }
  ]
}

# Register and update service
aws ecs register-task-definition --cli-input-json file://task-definition.json
aws ecs update-service --cluster prod-cluster --service myapp --task-definition myapp:N --force-new-deployment

# View logs
aws logs tail /ecs/myapp --follow
```

---

## Audit & Compliance

### Check Deployment History

```bash
# List all deployment records
ls -la build-artifacts/deployment-*.json

# View specific deployment
cat build-artifacts/deployment-1.0.0.json | jq '.'
```

### Verify Deployment Chain

```bash
# For version 1.0.0:
# 1. See what was built
cat build-artifacts/attestation-1.0.0.json

# 2. See what vulnerabilities were found
cat build-artifacts/trivy-report-1.0.0.json

# 3. See what was deployed
cat build-artifacts/deployment-1.0.0.json

# 4. Verify with production registry
az acr repository show-tags --name myregistry --repository myapp
```

---

## Security Best Practices

1. **Restrict Access**
   - Pipeline 1: Available to developers/CI
   - Pipeline 2: Available only to approved operators (gated)

2. **Audit Everything**
   - All artifacts stored with version
   - Deployment record shows who, when, what
   - Can audit against git history

3. **Immutable Images**
   - Once signed and pushed to internal, don't modify
   - If changes needed, rebuild (Pipeline 1)

4. **Staged Deployment**
   - Internal registry = testing/staging
   - Production registry = approved for deployment

5. **Environment Secrets**
   ```bash
   # Never commit secrets
   export ACR_REGISTRY="..."
   export ECR_REGISTRY="..."
   export INTERNAL_REGISTRY_USER="..."
   export INTERNAL_REGISTRY_PASS="..."
   
   # Use GitHub Secrets, GitLab CI/CD Variables, or AWS Secrets Manager
   ```

---

## Summary

| Phase | Responsibility | Gate | Output |
|-------|-----------------|------|--------|
| **Pipeline 1: Build** | Developers/CI | Code commit | Signed image + artifacts in internal registry |
| **Pipeline 2: Deploy** | Operators/Approval | Deployment window | Validated image in production registry |
| **ACS/ECS** | Infrastructure | Resource availability | Running container |

**This model ensures:**
- ✅ Code quality checks before build
- ✅ Security scanning before signing
- ✅ Approval before production deployment
- ✅ Full audit trail for compliance
- ✅ Easy rollback (keep previous versions)
