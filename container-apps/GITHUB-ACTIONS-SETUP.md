# GitHub Actions Setup Guide

## Secrets Required

Go to your GitHub repository → **Settings → Secrets and variables → Actions**

### Pipeline 1 Secrets (Build)

| Secret | Value | Example |
|--------|-------|---------|
| `INTERNAL_REGISTRY_USER` | Username for internal registry | `automation` |
| `INTERNAL_REGISTRY_PASSWORD` | Password for internal registry | `<token>` |

**Setup:**
```bash
gh secret set INTERNAL_REGISTRY_USER --body "username"
gh secret set INTERNAL_REGISTRY_PASSWORD --body "password"
```

---

### Pipeline 2 Secrets (Azure ACR)

| Secret | Value | Example |
|--------|-------|---------|
| `AZURE_CLIENT_ID` | Azure service principal client ID | `12345678-1234-1234-1234-123456789012` |
| `AZURE_TENANT_ID` | Azure tenant ID | `12345678-1234-1234-1234-123456789012` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `12345678-1234-1234-1234-123456789012` |
| `ACR_REGISTRY_NAME` | ACR registry name (without .azurecr.io) | `myregistry` |
| `ACR_REGISTRY_URL` | Full ACR URL | `myregistry.azurecr.io` |

**Setup Azure:**

1. Create service principal:
```bash
az ad sp create-for-rbac \
  --name "github-actions" \
  --role "Contributor" \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```

2. Set secrets:
```bash
gh secret set AZURE_CLIENT_ID --body "appId"
gh secret set AZURE_TENANT_ID --body "tenant"
gh secret set AZURE_SUBSCRIPTION_ID --body "subscriptionId"
gh secret set ACR_REGISTRY_NAME --body "myregistry"
gh secret set ACR_REGISTRY_URL --body "myregistry.azurecr.io"
```

---

### Pipeline 2 Secrets (AWS ECR)

| Secret | Value | Example |
|--------|-------|---------|
| `AWS_ROLE_TO_ASSUME` | IAM role ARN for OIDC | `arn:aws:iam::123456789012:role/github-actions` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `ECR_REGISTRY_URL` | ECR registry URL | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |

**Setup AWS:**

1. Create IAM role for GitHub OIDC:
```bash
# Create trust policy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name github-actions \
  --assume-role-policy-document file://trust-policy.json
```

2. Attach ECR policy:
```bash
# Create ECR policy
cat > ecr-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:*:ACCOUNT_ID:repository/*"
    }
  ]
}
EOF

# Attach policy
aws iam put-role-policy \
  --role-name github-actions \
  --policy-name ecr-push \
  --policy-document file://ecr-policy.json
```

3. Set secrets:
```bash
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/github-actions"
gh secret set AWS_REGION --body "us-east-1"
gh secret set ECR_REGISTRY_URL --body "123456789012.dkr.ecr.us-east-1.amazonaws.com"
```

---

## Environments (Optional but Recommended)

GitHub Environments add extra security gates. Create via **Settings → Environments**

### Staging Environment
- No approval required
- Runs on `workflow_dispatch` manually

### Production Environment
- **Requires manual approval** before running
- Set reviewers: Only certain team members can approve
- Deployment protection rules: Restrict who can deploy

**Add environment:**
```
Settings → Environments → New Environment
Name: production
Required reviewers: Select team members
Deployment protection rules: (optional)
```

---

## Verify Setup

### Test Pipeline 1
```bash
# Trigger manually
gh workflow run pipeline1-build.yml --ref main
```

Check:
- ✅ Build succeeds
- ✅ Image pushed to internal registry
- ✅ Artifacts uploaded

### Test Pipeline 2
```bash
# Trigger manually with inputs
gh workflow run pipeline2-deploy.yml \
  --ref main \
  -f version=1.0.0 \
  -f cloud_provider=acr \
  -f environment=staging
```

Check:
- ✅ Artifacts downloaded
- ✅ Vulnerabilities checked
- ✅ Image pushed to production
- ✅ Deployment record created

---

## File Structure

Your repository should look like:

```
your-repo/
├── .github/
│   └── workflows/
│       ├── pipeline1-build.yml      ← Automatic on push/tag
│       └── pipeline2-deploy.yml     ← Manual workflow_dispatch
├── Dockerfile                        ← OWASP hardened
├── .dockerignore
├── src/                              ← Your app code
├── package.json
└── README.md
```

---

## How It Works

### Pipeline 1: Automatic (on push to main or tag)

```mermaid
git push
    ↓
workflow_run triggered
    ↓
Build Docker image
    ↓
Scan (Trivy)
    ↓
Sign (Cosign)
    ↓
Generate SBOM
    ↓
Push to internal registry
    ↓
Upload artifacts
```

### Pipeline 2: Manual (workflow_dispatch)

Trigger via:
- GitHub UI (Actions tab → Pipeline 2 → Run workflow)
- CLI: `gh workflow run pipeline2-deploy.yml -f version=1.0.0 -f cloud_provider=acr`
- REST API

```mermaid
workflow_dispatch
    ↓
Download artifacts
    ↓
Validate vulnerabilities
    ↓
Verify signature
    ↓
Authenticate to ACR/ECR
    ↓
Push to production
    ↓
Create deployment record
```

---

## Common Issues

### "Artifact not found"
- Make sure Pipeline 1 ran successfully
- Check artifact name matches: `build-artifacts-<version>`
- Artifacts are retained for 30 days by default

### "Failed to authenticate with ACR/ECR"
- Verify secrets are set correctly
- For Azure: Check service principal has ACR permissions
- For AWS: Verify role trust policy and ECR permissions

### "CRITICAL vulnerabilities found"
- Pipeline 2 will block deployment
- Review `trivy-report.json` from Pipeline 1
- Update base image or dependencies and re-run Pipeline 1

### "Container running as root"
- Verify Dockerfile has `USER appuser` before `CMD`
- Re-run Pipeline 1 after fix

---

## Viewing Logs

### In GitHub UI
1. Go to **Actions** tab
2. Click workflow name (Pipeline 1 or 2)
3. Click the run
4. Click a step to see logs

### Via CLI
```bash
# Watch live
gh run watch

# View specific run
gh run view <run-id> --log

# List recent runs
gh run list --workflow=pipeline1-build.yml --limit=10
```

---

## Troubleshooting

### Check workflow syntax
```bash
gh workflow view .github/workflows/pipeline1-build.yml
```

### Manually trigger workflow
```bash
gh workflow run pipeline1-build.yml --ref main
```

### View workflow runs
```bash
gh run list --workflow=pipeline1-build.yml

# View specific run
gh run view 12345678 --log
```

### Re-run a failed workflow
```bash
gh run rerun 12345678
```

---

## Security Best Practices

1. **Use Secrets, Not Environment Variables**
   - Secrets are masked in logs
   - Environment variables are visible in workflow files

2. **Use GitHub Environments**
   - Set deployment protection rules
   - Require reviewers for production
   - Restrict with branch/tag patterns

3. **Use OIDC (Not Static Credentials)**
   - Better for AWS (no long-lived credentials)
   - Azure also supports it
   - Credentials are short-lived

4. **Restrict Workflow Permissions**
   ```yaml
   permissions:
     contents: read
     packages: write
     security-events: write
     id-token: write  # For OIDC
   ```

5. **Regular Secret Rotation**
   - Change internal registry credentials every 90 days
   - Rotate service principal keys regularly

---

## Example: Complete Secrets Setup

```bash
# Internal Registry (Pipeline 1)
gh secret set INTERNAL_REGISTRY_USER --body "automation-bot"
gh secret set INTERNAL_REGISTRY_PASSWORD --body "super-secret-token"

# Azure (Pipeline 2)
gh secret set AZURE_CLIENT_ID --body "00000000-0000-0000-0000-000000000000"
gh secret set AZURE_TENANT_ID --body "11111111-1111-1111-1111-111111111111"
gh secret set AZURE_SUBSCRIPTION_ID --body "22222222-2222-2222-2222-222222222222"
gh secret set ACR_REGISTRY_NAME --body "myregistry"
gh secret set ACR_REGISTRY_URL --body "myregistry.azurecr.io"

# OR AWS (Pipeline 2)
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/github-actions"
gh secret set AWS_REGION --body "us-east-1"
gh secret set ECR_REGISTRY_URL --body "123456789012.dkr.ecr.us-east-1.amazonaws.com"
```

Done! 🎉

Your GitHub Actions are now configured for a secure two-pipeline deployment model.
