#!/usr/bin/env bash
set -euo pipefail

# Deploy to Azure Container Instances
# Usage: ./azure/deploy-aci.sh <resource-group> <acr-name> [container-name]

RESOURCE_GROUP="${1:-canada-agent-rg}"
ACR_NAME="${2:-canadaagent}"
CONTAINER_NAME="${3:-canada-agent-backend}"
IMAGE_NAME="canada-agent-backend"
IMAGE_TAG="${4:-latest}"

echo "=========================================="
echo "  Deploying to Azure Container Instances"
echo "=========================================="
echo ""

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

echo "Resource Group: $RESOURCE_GROUP"
echo "Container Name: $CONTAINER_NAME"
echo "Image: $FULL_IMAGE_NAME"
echo ""

# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query passwords[0].value -o tsv)

# Prompt for OpenAI API key if not set
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Enter your OpenAI API key (or set OPENAI_API_KEY environment variable):"
  read -s OPENAI_API_KEY
  echo ""
fi

# Create or update container instance
echo "Creating/updating container instance..."
az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_NAME" \
  --image "$FULL_IMAGE_NAME" \
  --registry-login-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --dns-name-label "${CONTAINER_NAME}-$(date +%s)" \
  --ports 8000 \
  --cpu 1 \
  --memory 1 \
  --environment-variables \
    OPENAI_API_KEY="$OPENAI_API_KEY" \
    OPENAI_MODEL="${OPENAI_MODEL:-gpt-4}" \
    CORS_ALLOW_ORIGINS="${CORS_ALLOW_ORIGINS:-*}" \
  --restart-policy Always \
  --output table

# Get the FQDN
FQDN=$(az container show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_NAME" \
  --query ipAddress.fqdn -o tsv)

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
echo ""
echo "Container is running at:"
echo "  http://$FQDN:8000"
echo "  https://$FQDN:8000 (if HTTPS enabled)"
echo ""
echo "API Documentation:"
echo "  http://$FQDN:8000/docs"
echo ""
echo "Health Check:"
echo "  http://$FQDN:8000/healthz"
echo ""
echo "To view logs:"
echo "  az container logs --resource-group $RESOURCE_GROUP --name $CONTAINER_NAME --follow"
echo ""
