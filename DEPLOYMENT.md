# Deployment Guide

This project is production-ready for Azure Container Registry deployment.

## Quick Start

### 1. Deploy to Azure Container Registry

```bash
# Make scripts executable (if not already)
chmod +x azure/*.sh

# Deploy to ACR
./azure/deploy.sh canada-agent-rg canadaagent latest
```

### 2. Deploy to Azure Container Instances

```bash
export OPENAI_API_KEY="sk-your-key-here"
./azure/deploy-aci.sh canada-agent-rg canadaagent canada-agent-backend latest
```

### 3. Deploy to Azure App Service

```bash
export OPENAI_API_KEY="sk-your-key-here"
./azure/deploy-app-service.sh canada-agent-rg canadaagent canada-agent-backend latest
```

## Production Features

### Dockerfile Improvements

✅ **Multi-stage build** - Smaller final image (~200MB vs ~800MB)  
✅ **Non-root user** - Runs as `appuser` (UID 1000) for security  
✅ **Health checks** - Automatic container health monitoring  
✅ **Minimal dependencies** - Only runtime requirements in final image  
✅ **Optimized layers** - Better caching and faster builds  

### Security Enhancements

- Runs as non-root user
- Minimal attack surface (slim base image)
- No unnecessary packages
- Health check endpoint for monitoring

### Azure Integration

- **ACR** - Private container registry
- **ACI** - Serverless containers
- **App Service** - Managed web app platform
- **CI/CD** - Azure DevOps pipeline ready

## Testing Locally

### Test Production Image

```bash
# Build production image
cd backend
docker build -t canada-agent-backend:latest .

# Run locally
docker run -p 8000:8000 \
  -e OPENAI_API_KEY="sk-your-key" \
  -e OPENAI_MODEL="gpt-4" \
  canada-agent-backend:latest

# Or use docker-compose
docker-compose -f docker-compose.prod.yml up
```

### Verify Health Check

```bash
curl http://localhost:8000/healthz
```

## File Structure

```
.
├── backend/
│   ├── Dockerfile              # Production-ready multi-stage build
│   ├── .dockerignore          # Optimized ignore patterns
│   └── app/                   # Application code
├── azure/
│   ├── deploy.sh              # Build and push to ACR
│   ├── deploy-aci.sh          # Deploy to Container Instances
│   ├── deploy-app-service.sh   # Deploy to App Service
│   ├── azure-pipelines.yml    # CI/CD pipeline
│   └── README.md              # Detailed Azure guide
└── docker-compose.prod.yml    # Local production testing
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | Yes | - | OpenAI API key |
| `OPENAI_MODEL` | No | `gpt-4` | Model to use |
| `CORS_ALLOW_ORIGINS` | No | `*` | CORS allowed origins |

## Monitoring

### Health Endpoint

```bash
GET /healthz
```

Returns `200 OK` if the service is healthy.

### Logs

**Container Instances:**
```bash
az container logs --resource-group canada-agent-rg --name canada-agent-backend --follow
```

**App Service:**
```bash
az webapp log tail --name canada-agent-backend --resource-group canada-agent-rg
```

## Cost Optimization

- **Multi-stage build** reduces image size → faster pulls
- **Slim base image** reduces storage costs
- **Health checks** enable auto-restart → better reliability
- **Resource limits** prevent over-provisioning

## Next Steps

1. **Set up CI/CD** - Use `azure/azure-pipelines.yml`
2. **Configure monitoring** - Azure Application Insights
3. **Set up secrets** - Azure Key Vault for API keys
4. **Enable HTTPS** - App Service provides this automatically
5. **Custom domain** - Configure in App Service settings

For detailed Azure deployment instructions, see [azure/README.md](azure/README.md).
