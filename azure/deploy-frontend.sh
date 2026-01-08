#!/usr/bin/env bash
set -euo pipefail

# Deploy FRONTEND container to Azure App Service (Linux Container)
# Usage:
#   ./azure/deploy-frontend.sh <resource-group> <acr-name> [app-name] [image-tag]
#
# Example:
#   ./azure/deploy-frontend.sh my-rg myacr my-frontend latest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
APP_NAME="${3:-${AZURE_FRONTEND_APP_NAME:-canada-agent-frontend}}"
IMAGE_TAG="${4:-${AZURE_IMAGE_TAG:-latest}}"

IMAGE_NAME="canada-agent-frontend"
APP_SERVICE_PLAN="${APP_NAME}-plan"

echo "=========================================="
echo "  Deploying Frontend to Azure App Service"
echo "=========================================="
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

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

echo "Resource Group: $RESOURCE_GROUP"
echo "App Service:    $APP_NAME"
echo "Image:          $FULL_IMAGE_NAME"
echo ""

# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query passwords[0].value -o tsv)

echo "Creating App Service Plan (if not exists)..."
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --is-linux \
  --sku B1 \
  --output none 2>/dev/null || echo "App Service Plan already exists"

echo "Creating Web App (if not exists)..."
az webapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_SERVICE_PLAN" \
  --deployment-container-image-name "$FULL_IMAGE_NAME" \
  --output none 2>/dev/null || echo "Web App already exists"

echo "Configuring container settings..."
az webapp config container set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --docker-custom-image-name "$FULL_IMAGE_NAME" \
  --docker-registry-server-url "https://$ACR_LOGIN_SERVER" \
  --docker-registry-server-user "$ACR_USERNAME" \
  --docker-registry-server-password "$ACR_PASSWORD" \
  --output none

echo "Configuring app settings..."
az webapp config appsettings set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    WEBSITES_PORT=3000 \
  --output none

echo "Enabling continuous deployment..."
az webapp deployment container config \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-cd true \
  --output none

APP_URL=$(az webapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query defaultHostName -o tsv)

echo ""
echo "=========================================="
echo "  Frontend Deployment Complete!"
echo "=========================================="
echo ""
echo "Frontend URL:"
echo "  https://$APP_URL"

