#!/usr/bin/env bash
set -euo pipefail

# Deploy to Azure App Service (Linux Container)
# Usage: ./azure/deploy-app-service.sh <resource-group> <acr-name> [app-name]

RESOURCE_GROUP="${1:-canada-agent-rg}"
ACR_NAME="${2:-canadaagent}"
APP_NAME="${3:-canada-agent-backend}"
IMAGE_NAME="canada-agent-backend"
IMAGE_TAG="${4:-latest}"
APP_SERVICE_PLAN="${APP_NAME}-plan"

echo "=========================================="
echo "  Deploying to Azure App Service"
echo "=========================================="
echo ""

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

echo "Resource Group: $RESOURCE_GROUP"
echo "App Service: $APP_NAME"
echo "Image: $FULL_IMAGE_NAME"
echo ""

# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query passwords[0].value -o tsv)

# Create App Service Plan (if not exists)
echo "Creating App Service Plan..."
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --is-linux \
  --sku B1 \
  --output none 2>/dev/null || echo "App Service Plan already exists"

# Create Web App (if not exists)
echo "Creating Web App..."
az webapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_SERVICE_PLAN" \
  --deployment-container-image-name "$FULL_IMAGE_NAME" \
  --output none 2>/dev/null || echo "Web App already exists"

# Configure container settings
echo "Configuring container settings..."
az webapp config container set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --docker-custom-image-name "$FULL_IMAGE_NAME" \
  --docker-registry-server-url "https://$ACR_LOGIN_SERVER" \
  --docker-registry-server-user "$ACR_USERNAME" \
  --docker-registry-server-password "$ACR_PASSWORD"

# Configure app settings
echo "Configuring app settings..."

# Prompt for OpenAI API key if not set
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Enter your OpenAI API key (or set OPENAI_API_KEY environment variable):"
  read -s OPENAI_API_KEY
  echo ""
fi

az webapp config appsettings set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    OPENAI_API_KEY="$OPENAI_API_KEY" \
    OPENAI_MODEL="${OPENAI_MODEL:-gpt-4}" \
    CORS_ALLOW_ORIGINS="${CORS_ALLOW_ORIGINS:-*}" \
    WEBSITES_PORT=8000 \
  --output none

# Enable continuous deployment
echo "Enabling continuous deployment..."
az webapp deployment container config \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-cd true \
  --output none

# Get the app URL
APP_URL=$(az webapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query defaultHostName -o tsv)

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
echo ""
echo "App is running at:"
echo "  https://$APP_URL"
echo ""
echo "API Documentation:"
echo "  https://$APP_URL/docs"
echo ""
echo "Health Check:"
echo "  https://$APP_URL/healthz"
echo ""
echo "To view logs:"
echo "  az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
