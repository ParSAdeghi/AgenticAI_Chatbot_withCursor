# Azure Deployment Guide

This guide walks you through deploying the Canada Tourist Chatbot backend to Azure using Azure Container Registry (ACR).

## Prerequisites

1. **Azure CLI** installed and configured
   ```bash
   # Install Azure CLI
   # Windows: https://aka.ms/installazurecliwindows
   # macOS: brew install azure-cli
   # Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Login
   az login
   ```

2. **Docker** installed and running

3. **OpenAI API Key** - You'll need this for the deployment

## Quick Start

### 1. Deploy to Azure Container Registry

```bash
# Make scripts executable
chmod +x azure/*.sh

# Deploy to ACR (creates resource group and ACR if needed)
./azure/deploy.sh <resource-group-name> <acr-name> <image-tag>

# Example:
./azure/deploy.sh canada-agent-rg canadaagent latest
```

This will:
- Create a resource group (if it doesn't exist)
- Create an Azure Container Registry (if it doesn't exist)
- Build the Docker image
- Push the image to ACR

### 2. Deploy to Azure Container Instances (ACI)

```bash
# Deploy to ACI
./azure/deploy-aci.sh <resource-group> <acr-name> [container-name] [image-tag]

# Example:
./azure/deploy-aci.sh canada-agent-rg canadaagent canada-agent-backend latest
```

This creates a container instance that:
- Runs on Azure's managed infrastructure
- Has a public IP and DNS name
- Automatically restarts on failure
- Scales manually (use Azure Container Apps for auto-scaling)

### 3. Deploy to Azure App Service

```bash
# Deploy to App Service
./azure/deploy-app-service.sh <resource-group> <acr-name> [app-name] [image-tag]

# Example:
./azure/deploy-app-service.sh canada-agent-rg canadaagent canada-agent-backend latest
```

This creates an App Service that:
- Provides HTTPS by default
- Supports custom domains
- Has built-in monitoring and logging
- Can auto-scale based on traffic

## Manual Deployment Steps

### Step 1: Create Resource Group

```bash
az group create --name canada-agent-rg --location eastus
```

### Step 2: Create Azure Container Registry

```bash
az acr create \
  --resource-group canada-agent-rg \
  --name canadaagent \
  --sku Basic \
  --admin-enabled true
```

### Step 3: Build and Push Image

```bash
# Login to ACR
az acr login --name canadaagent

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name canadaagent --resource-group canada-agent-rg --query loginServer -o tsv)

# Build image
cd backend
docker build -t canada-agent-backend:latest .

# Tag for ACR
docker tag canada-agent-backend:latest $ACR_LOGIN_SERVER/canada-agent-backend:latest

# Push to ACR
docker push $ACR_LOGIN_SERVER/canada-agent-backend:latest
```

### Step 4: Deploy to Container Instances

```bash
# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name canadaagent --resource-group canada-agent-rg --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name canadaagent --resource-group canada-agent-rg --query passwords[0].value -o tsv)

# Create container instance
az container create \
  --resource-group canada-agent-rg \
  --name canada-agent-backend \
  --image $ACR_LOGIN_SERVER/canada-agent-backend:latest \
  --registry-login-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --dns-name-label canada-agent-$(date +%s) \
  --ports 8000 \
  --cpu 1 \
  --memory 1 \
  --environment-variables \
    OPENAI_API_KEY="sk-your-key-here" \
    OPENAI_MODEL="gpt-4" \
    CORS_ALLOW_ORIGINS="*" \
  --restart-policy Always
```

### Step 5: Get Container URL

```bash
az container show \
  --resource-group canada-agent-rg \
  --name canada-agent-backend \
  --query ipAddress.fqdn -o tsv
```

## Environment Variables

The following environment variables can be configured:

- `OPENAI_API_KEY` (required) - Your OpenAI API key
- `OPENAI_MODEL` (optional) - Model to use (default: `gpt-4`)
- `CORS_ALLOW_ORIGINS` (optional) - CORS allowed origins (default: `*`)

## Monitoring and Logs

### View Container Logs (ACI)

```bash
az container logs \
  --resource-group canada-agent-rg \
  --name canada-agent-backend \
  --follow
```

### View App Service Logs

```bash
az webapp log tail \
  --name canada-agent-backend \
  --resource-group canada-agent-rg
```

### Monitor Metrics

```bash
# Container Instances
az monitor metrics list \
  --resource /subscriptions/{subscription-id}/resourceGroups/canada-agent-rg/providers/Microsoft.ContainerInstance/containerGroups/canada-agent-backend

# App Service
az monitor metrics list \
  --resource /subscriptions/{subscription-id}/resourceGroups/canada-agent-rg/providers/Microsoft.Web/sites/canada-agent-backend
```

## Updating the Deployment

### Update Container Image

```bash
# Rebuild and push
./azure/deploy.sh canada-agent-rg canadaagent v1.1.0

# Restart container (ACI)
az container restart \
  --resource-group canada-agent-rg \
  --name canada-agent-backend

# Or update App Service (auto-updates with continuous deployment)
az webapp restart \
  --name canada-agent-backend \
  --resource-group canada-agent-rg
```

## Cost Estimation

### Azure Container Instances
- **Basic tier**: ~$0.000012/second (~$31/month for 1 CPU, 1GB RAM, always running)
- Pay only for running time

### Azure App Service
- **B1 (Basic)**: ~$13/month
- Includes HTTPS, custom domains, auto-scaling

### Azure Container Registry
- **Basic tier**: $5/month + storage costs
- First 10GB free, then $0.167/GB/month

## Security Best Practices

1. **Use Azure Key Vault** for secrets:
   ```bash
   # Create Key Vault
   az keyvault create --name canada-agent-kv --resource-group canada-agent-rg
   
   # Store OpenAI API key
   az keyvault secret set --vault-name canada-agent-kv --name OpenAIApiKey --value "sk-..."
   
   # Reference in deployment
   az container create ... \
     --secrets \
       OPENAI_API_KEY=$(az keyvault secret show --vault-name canada-agent-kv --name OpenAIApiKey --query value -o tsv)
   ```

2. **Enable ACR admin** only for testing. Use managed identity for production.

3. **Restrict CORS** origins in production:
   ```bash
   CORS_ALLOW_ORIGINS="https://your-frontend-domain.com"
   ```

4. **Use Private Endpoints** for ACR in production environments.

## Troubleshooting

### Container won't start
```bash
# Check logs
az container logs --resource-group canada-agent-rg --name canada-agent-backend

# Check events
az container show --resource-group canada-agent-rg --name canada-agent-backend --query containers[0].instanceView.currentState
```

### Image pull errors
```bash
# Verify ACR credentials
az acr credential show --name canadaagent --resource-group canada-agent-rg

# Test ACR login
az acr login --name canadaagent
```

### Health check failures
```bash
# Test health endpoint
curl http://<container-fqdn>:8000/healthz

# Check container status
az container show --resource-group canada-agent-rg --name canada-agent-backend --query containers[0].instanceView.currentState
```

## Next Steps

- Set up **Azure Container Apps** for auto-scaling
- Configure **Application Insights** for monitoring
- Set up **Azure Front Door** for global distribution
- Implement **Azure DevOps** pipeline for CI/CD
