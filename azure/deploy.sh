#!/usr/bin/env bash
set -euo pipefail

# Azure Container Registry Deployment Script
# Usage: ./azure/deploy.sh <resource-group> <acr-name> <image-tag>

RESOURCE_GROUP="${1:-canada-agent-rg}"
ACR_NAME="${2:-canadaagent}"
IMAGE_TAG="${3:-latest}"
IMAGE_NAME="canada-agent-backend"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "  Azure Container Registry Deployment"
echo "=========================================="
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "ACR Name: $ACR_NAME"
echo "Image: $IMAGE_NAME:$IMAGE_TAG"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI not found. Please install it first:"
  echo "  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
  echo "Logging in to Azure..."
  az login
fi

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
echo "Current subscription: $SUBSCRIPTION"
echo ""

# Create resource group if it doesn't exist
echo "Creating resource group (if not exists)..."
az group create --name "$RESOURCE_GROUP" --location eastus 2>/dev/null || \
  echo "Resource group already exists"

# Create ACR if it doesn't exist
echo "Creating Azure Container Registry (if not exists)..."
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled true \
  2>/dev/null || echo "ACR already exists"

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
echo "ACR Login Server: $ACR_LOGIN_SERVER"
echo ""

# Build the Docker image
echo "Building Docker image..."
cd "$PROJECT_ROOT/backend"
docker build -t "$IMAGE_NAME:$IMAGE_TAG" .

# Tag for ACR
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
echo "Tagging image for ACR: $FULL_IMAGE_NAME"
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$FULL_IMAGE_NAME"

# Login to ACR
echo "Logging in to ACR..."
az acr login --name "$ACR_NAME"

# Push to ACR
echo "Pushing image to ACR..."
docker push "$FULL_IMAGE_NAME"

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
echo ""
echo "Image pushed to: $FULL_IMAGE_NAME"
echo ""
echo "Next steps:"
echo "  1. Deploy to Azure Container Instances:"
echo "     ./azure/deploy-aci.sh $RESOURCE_GROUP $ACR_NAME"
echo ""
echo "  2. Or deploy to Azure App Service:"
echo "     ./azure/deploy-app-service.sh $RESOURCE_GROUP $ACR_NAME"
echo ""
