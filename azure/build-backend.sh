#!/usr/bin/env bash
set -euo pipefail

# Build and push BACKEND Docker image to Azure Container Registry (ACR)
# Usage: ./azure/build-backend.sh <resource-group> <acr-name> <image-tag>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional local-only config file (DO NOT COMMIT secrets)
# Supports either azure/.env.azure or azure/env.azure
for f in "$SCRIPT_DIR/.env.azure" "$SCRIPT_DIR/env.azure"; do
  if [[ -f "$f" ]]; then
    echo "[deploy] Loading Azure config from: $f"
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    break
  fi
done

RESOURCE_GROUP="${1:-${AZURE_RESOURCE_GROUP:-canada-agent-rg}}"
ACR_NAME="${2:-${AZURE_ACR_NAME:-canadaagent}}"
IMAGE_TAG="${3:-${AZURE_IMAGE_TAG:-latest}}"
IMAGE_NAME="canada-agent-backend"

echo "=========================================="
echo "  Building & Pushing Backend Docker Image"
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
  if [[ -n "${AZURE_TENANT_ID:-}" && -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
    echo "Logging in to Azure using service principal..."
    az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null
    if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
      az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    fi
  else
    echo "Logging in to Azure..."
    az login
  fi
fi

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
echo "Current subscription: $SUBSCRIPTION"
echo ""

# Create resource group if it doesn't exist
echo "Creating resource group (if not exists)..."
az group create --name "$RESOURCE_GROUP" --location "${AZURE_LOCATION:-eastus}" 2>/dev/null || \
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
echo "  Build & Push Complete!"
echo "=========================================="
echo ""
echo "Backend image pushed to: $FULL_IMAGE_NAME"
echo ""
echo "Next steps:"
echo "  1. Deploy to Azure Container Instances:"
echo "     ./azure/deploy-backend.sh aci $RESOURCE_GROUP $ACR_NAME"
echo ""
echo "  2. Or deploy to Azure App Service:"
echo "     ./azure/deploy-backend.sh app-service $RESOURCE_GROUP $ACR_NAME"
echo ""
