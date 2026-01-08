#!/usr/bin/env bash
set -euo pipefail

# Build and push FRONTEND Docker image to Azure Container Registry (ACR)
# Usage:
#   ./azure/build-frontend.sh <resource-group> <acr-name> <image-tag> <backend-url>
#
# Example:
#   ./azure/build-frontend.sh my-rg myacr latest https://my-aci.eastus.azurecontainer.io:8000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional local-only config file (DO NOT COMMIT secrets)
for f in "$SCRIPT_DIR/.env.azure" "$SCRIPT_DIR/env.azure"; do
  if [[ -f "$f" ]]; then
    echo "[deploy-frontend] Loading Azure config from: $f"
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
BACKEND_URL="${4:-${NEXT_PUBLIC_BACKEND_URL:-}}"

IMAGE_NAME="canada-agent-frontend"

if [[ -z "$BACKEND_URL" ]]; then
  echo "ERROR: backend-url is required (used to set NEXT_PUBLIC_BACKEND_URL at build time)."
  echo "Usage: ./azure/build-frontend.sh <rg> <acr> <tag> <backend-url>"
  exit 1
fi

echo "=========================================="
echo "  Azure ACR - Build & Push Frontend"
echo "=========================================="
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "ACR Name:       $ACR_NAME"
echo "Image:          $IMAGE_NAME:$IMAGE_TAG"
echo "Backend URL:    $BACKEND_URL"
echo ""

if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI not found. Please install it first:"
  echo "  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  exit 1
fi

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

echo "Creating resource group (if not exists)..."
az group create --name "$RESOURCE_GROUP" --location "${AZURE_LOCATION:-eastus}" 2>/dev/null || \
  echo "Resource group already exists"

echo "Creating Azure Container Registry (if not exists)..."
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled true \
  2>/dev/null || echo "ACR already exists"

ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

echo "ACR Login Server: $ACR_LOGIN_SERVER"
echo "Full Image Name:  $FULL_IMAGE_NAME"
echo ""

echo "Building frontend Docker image..."
cd "$PROJECT_ROOT/frontend"
docker build \
  --build-arg NEXT_PUBLIC_BACKEND_URL="$BACKEND_URL" \
  -t "$IMAGE_NAME:$IMAGE_TAG" \
  .

echo "Tagging image for ACR..."
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$FULL_IMAGE_NAME"

echo "Logging in to ACR..."
az acr login --name "$ACR_NAME"

echo "Pushing image to ACR..."
docker push "$FULL_IMAGE_NAME"

echo ""
echo "=========================================="
echo "  Frontend Image Pushed!"
echo "=========================================="
echo ""
echo "Image: $FULL_IMAGE_NAME"

