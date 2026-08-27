# GitHub Actions Quick Start

## 1. Copy Workflow Files

```bash
mkdir -p .github/workflows
cp pipeline1-build.yml .github/workflows/
cp pipeline2-deploy.yml .github/workflows/
```

## 2. Set Secrets (5 mins)

### For Azure (ACR)
```bash
# Internal registry credentials (for Pipeline 1)
gh secret set INTERNAL_REGISTRY_USER --body "your-username"
gh secret set INTERNAL_REGISTRY_PASSWORD --body "your-password"

# Azure credentials (for Pipeline 2)
gh secret set AZURE_CLIENT_ID --body "..."
gh secret set AZURE_TENANT_ID --body "..."
gh secret set AZURE_SUBSCRIPTION_ID --body "..."
gh secret set ACR_REGISTRY_NAME --body "myregistry"
gh secret set ACR_REGISTRY_URL --body "myregistry.azurecr.io"
```

### For AWS (ECR)
```bash
# Internal registry credentials (for Pipeline 1)
gh secret set INTERNAL_REGISTRY_USER --body "your-username"
gh secret set INTERNAL_REGISTRY_PASSWORD --body "your-password"

# AWS credentials (for Pipeline 2 - using OIDC)
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/github-actions"
gh secret set AWS_REGION --body "us-east-1"
gh secret set ECR_REGISTRY_URL --body "123456789012.dkr.ecr.us-east-1.amazonaws.com"
```

See `GITHUB-ACTIONS-SETUP.md` for detailed setup.

## 3. Push Code

```bash
git add Dockerfile .dockerignore .github/workflows/
git commit -m "Add GitHub Actions pipelines"
git push origin main
```

Pipeline 1 **automatically runs** on push.

## 4. Monitor Pipeline 1

Go to GitHub → **Actions** tab

Watch:
- ✅ Build Docker image
- ✅ Scan with Trivy
- ✅ Generate SBOM
- ✅ Sign image
- ✅ Push to internal registry
- ✅ Upload artifacts

## 5. Deploy (When Ready)

### Via GitHub UI
1. Go to **Actions**
2. Click **"Pipeline 2 - Validate & Deploy to Production"**
3. Click **"Run workflow"**
4. Enter:
   - **Version:** `1.0.0` (or use commit SHA)
   - **Cloud provider:** `acr` or `ecr`
   - **Environment:** `staging` or `production`
5. Click **"Run workflow"**

### Via CLI
```bash
# Deploy to ACR production
gh workflow run pipeline2-deploy.yml \
  -f version=1.0.0 \
  -f cloud_provider=acr \
  -f environment=production

# Deploy to ECR staging
gh workflow run pipeline2-deploy.yml \
  -f version=1.0.0 \
  -f cloud_provider=ecr \
  -f environment=staging
```

## 6. What Happens

### Pipeline 1 (Automatic on Push)
```
git push → Pipeline 1 starts
    ↓
Build + Scan (5 mins)
    ↓
Create Artifacts:
  - trivy-report.json
  - sbom-report.json
  - attestation.json
  - checksums.txt
    ↓
Push to internal registry
```

**Output:** Signed image in `registry.internal:5000`

### Pipeline 2 (Manual Deployment)
```
workflow_dispatch → Pipeline 2 starts
    ↓
Download artifacts
    ↓
Validate:
  - No CRITICAL vulns
  - Signature valid
  - Checksums match
    ↓
Push to production (ACR/ECR)
    ↓
Create deployment record
```

**Output:** Signed image in `myregistry.azurecr.io` or `ECR`

## 7. Deploy to ACS/ECS

### After Pipeline 2 succeeds:

**Azure ACS:**
```bash
az container create \
  --resource-group mygroup \
  --name myapp \
  --image myregistry.azurecr.io/myapp:1.0.0 \
  --ports 3000 \
  --cpu 1 --memory 1.0
```

**AWS ECS:**
```bash
# Update task definition, then:
aws ecs update-service \
  --cluster my-cluster \
  --service myapp \
  --task-definition myapp:2 \
  --force-new-deployment
```

## Workflow Structure

```
.github/
└── workflows/
    ├── pipeline1-build.yml
    │   ├── Trigger: push to main (automatic)
    │   ├── Jobs: build, scan, sign, push to internal
    │   └── Artifacts: trivy, sbom, attestation, checksums
    │
    └── pipeline2-deploy.yml
        ├── Trigger: manual (workflow_dispatch)
        ├── Input: version, cloud_provider, environment
        ├── Jobs: validate, authenticate, push to production
        └── Artifacts: deployment-record
```

## Status Badges

Add to your `README.md`:

```markdown
[![Build Status](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/pipeline1-build.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions)
[![Deploy Status](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/pipeline2-deploy.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions)
```

## Troubleshooting

**Pipeline 1 fails to build**
```bash
# Check workflow syntax
gh workflow view .github/workflows/pipeline1-build.yml

# View logs
gh run list --workflow=pipeline1-build.yml --limit=1
gh run view <run-id> --log
```

**Pipeline 1 succeeds but Pipeline 2 can't find artifacts**
- Artifacts are named: `build-artifacts-<version>`
- Check version matches in Pipeline 2 input
- Artifacts expire after 30 days

**Pipeline 2 fails to authenticate with ACR/ECR**
- Verify secrets are set: `gh secret list`
- For Azure: Check service principal has ACR roles
- For AWS: Verify IAM role and ECR permissions

**CRITICAL vulnerabilities block deployment**
- Review `trivy-report.json` in Pipeline 1 artifacts
- Update base image or dependencies
- Re-run Pipeline 1 after fix

## Next Steps

1. ✅ Copy workflow files
2. ✅ Set secrets
3. ✅ Push code
4. ✅ Watch Pipeline 1 succeed
5. ✅ Manually trigger Pipeline 2
6. ✅ Deploy to ACS/ECS

**You're done!** Every push builds a signed image. Every deployment is validated and audited.

---

## Key Features

✅ **Automatic build** on push (Pipeline 1)  
✅ **Manual approval** for production (Pipeline 2)  
✅ **Vulnerability scanning** (Trivy)  
✅ **Software SBOM** (Syft)  
✅ **Image signing** (Cosign)  
✅ **Full audit trail** (deployment records)  
✅ **Works with ACR & ECR**  
✅ **Zero manual steps** after setup  
