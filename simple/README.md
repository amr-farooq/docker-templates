# Build, Push to ACR/ECR, Deploy to ACS/ECS

## Setup (one-time)

### Azure (ACR → ACS)
```bash
# Login to Azure
az login

# Create ACR (Container Registry)
az acr create --resource-group mygroup --name myregistry --sku Basic

# Login to ACR
az acr login --name myregistry
```

### AWS (ECR → ECS)
```bash
# Configure AWS credentials
aws configure

# Create ECR (Container Registry)
aws ecr create-repository --repository-name myapp --region us-east-1

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456.dkr.ecr.us-east-1.amazonaws.com
```

---

## Build & Push to Registry

### Azure (ACR)
```bash
# Build
docker build -t myregistry.azurecr.io/myapp:1.0 .

# Push
docker push myregistry.azurecr.io/myapp:1.0

# Also tag as latest
docker tag myregistry.azurecr.io/myapp:1.0 myregistry.azurecr.io/myapp:latest
docker push myregistry.azurecr.io/myapp:latest
```

### AWS (ECR)
```bash
# Build
docker build -t 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0 .

# Push
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0

# Also tag as latest
docker tag 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
```

---

## Deploy to ACS (Azure Container Instances)

### Simple one-off deployment
```bash
az container create \
  --resource-group mygroup \
  --name myapp-instance \
  --image myregistry.azurecr.io/myapp:1.0 \
  --registry-login-server myregistry.azurecr.io \
  --registry-username <username> \
  --registry-password <password> \
  --ports 3000 \
  --environment-variables PORT=3000 \
  --cpu 1 --memory 1.0
```

### View logs
```bash
az container logs --resource-group mygroup --name myapp-instance
```

---

## Deploy to ECS (AWS)

### 1. Create a Task Definition (task-definition.json)
```json
{
  "family": "myapp",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "myapp",
      "image": "123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0",
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/myapp",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
        "interval": 30,
        "timeout": 10,
        "retries": 3,
        "startPeriod": 10
      }
    }
  ]
}
```

### 2. Register the task definition
```bash
aws ecs register-task-definition \
  --cli-input-json file://task-definition.json \
  --region us-east-1
```

### 3. Create ECS cluster (if you don't have one)
```bash
aws ecs create-cluster --cluster-name my-cluster --region us-east-1
```

### 4. Create a service
```bash
aws ecs create-service \
  --cluster my-cluster \
  --service-name myapp \
  --task-definition myapp:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=ENABLED}" \
  --region us-east-1
```

### 5. View service status
```bash
aws ecs describe-services \
  --cluster my-cluster \
  --services myapp \
  --region us-east-1
```

### 6. View logs
```bash
# First, see which task is running
aws ecs list-tasks --cluster my-cluster --region us-east-1

# Then view logs
aws logs tail /ecs/myapp --follow --region us-east-1
```

---

## Update deployment

### Azure (ACS)
```bash
# Update image
docker build -t myregistry.azurecr.io/myapp:1.1 .
docker push myregistry.azurecr.io/myapp:1.1

# Redeploy
az container create \
  --resource-group mygroup \
  --name myapp-instance \
  --image myregistry.azurecr.io/myapp:1.1 \
  --registry-login-server myregistry.azurecr.io \
  --registry-username <username> \
  --registry-password <password> \
  --ports 3000
```

### AWS (ECS)
```bash
# Update image
docker build -t 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.1 .
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:1.1

# Register new task definition
aws ecs register-task-definition \
  --cli-input-json file://task-definition.json \
  --region us-east-1

# Update service to use new task definition
aws ecs update-service \
  --cluster my-cluster \
  --service myapp \
  --task-definition myapp:2 \
  --force-new-deployment \
  --region us-east-1
```

---

## What's in the Dockerfile?

**Stage 1: Builder**
- Installs dependencies (npm ci --only=production = no dev stuff)
- Compiles code (npm run build)
- Creates a "compiled" version ready to run

**Stage 2: Runtime**
- Starts fresh (no build tools, much smaller)
- Copies only the compiled code and dependencies
- Creates non-root user (security)
- Health check (so ECS/ACS knows when container is healthy)
- Starts your app

**Result:** Image is ~150MB instead of 900MB, secure, and ready to deploy.

---

## Common Issues

**"docker: command not found"**
- Install Docker Desktop (macOS/Windows) or Docker Engine (Linux)

**"permission denied"** (Linux)
```bash
sudo usermod -aG docker $USER
newgrp docker
```

**"unauthorized" pushing to registry**
- Make sure you logged in: `az acr login` or `aws ecr get-login-password`

**Container crashes in ECS/ACS**
```bash
# Check logs
az container logs --resource-group mygroup --name myapp-instance
# or
aws logs tail /ecs/myapp --follow
```

**Health check failing**
- Make sure your app has a `/health` endpoint that returns 200 OK
- Or update HEALTHCHECK in Dockerfile to match your endpoint
