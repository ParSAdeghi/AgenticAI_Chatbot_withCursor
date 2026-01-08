#!/usr/bin/env bash
set -euo pipefail

# Deploy BACKEND to Azure (ACI or App Service)
# Usage: ./azure/deploy-backend.sh <target> <resource-group> <acr-name> [name] [image-tag]
#
# Targets:
#   aci          - Deploy to Azure Container Instances
#   app-service  - Deploy to Azure App Service
#
# Examples:
#   ./azure/deploy-backend.sh aci canada-agent-rg canadaagent
#   ./azure/deploy-backend.sh app-service canada-agent-rg canadaagent my-backend-app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional local-only config file (DO NOT COMMIT secrets)
for f in "$SCRIPT_DIR/.env.azure" "$SCRIPT_DIR/env.azure"; do
  if [[ -f "$f" ]]; then
    echo "[deploy-backend] Loading Azure config from: $f"
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    break
  fi
done

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "ERROR: Deployment target is required"
  echo ""
  echo "Usage: ./azure/deploy-backend.sh <target> <resource-group> <acr-name> [name] [image-tag]"
  echo ""
  echo "Targets:"
  echo "  aci          - Deploy to Azure Container Instances"
  echo "  app-service  - Deploy to Azure App Service"
  echo ""
  echo "Examples:"
  echo "  ./azure/deploy-backend.sh aci canada-agent-rg canadaagent"
  echo "  ./azure/deploy-backend.sh app-service canada-agent-rg canadaagent my-backend-app"
  exit 1
fi

if [[ "$TARGET" != "aci" && "$TARGET" != "app-service" ]]; then
  echo "ERROR: Invalid target '$TARGET'. Must be 'aci' or 'app-service'"
  exit 1
fi

RESOURCE_GROUP="${2:-${AZURE_RESOURCE_GROUP:-canada-agent-rg}}"
ACR_NAME="${3:-${AZURE_ACR_NAME:-canadaagent}}"
NAME="${4:-canada-agent-backend}"
IMAGE_NAME="canada-agent-backend"
IMAGE_TAG="${5:-${AZURE_IMAGE_TAG:-latest}}"

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

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query passwords[0].value -o tsv)

# Prompt for OpenAI API key if not set
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Enter your OpenAI API key (or set OPENAI_API_KEY environment variable):"
  read -s OPENAI_API_KEY
  echo ""
fi

# Deploy based on target
if [[ "$TARGET" == "aci" ]]; then
  echo "=========================================="
  echo "  Deploying to Azure Container Instances"
  echo "=========================================="
  echo ""
  echo "Resource Group: $RESOURCE_GROUP"
  echo "Container Name: $NAME"
  echo "Image: $FULL_IMAGE_NAME"
  echo ""

  # Use a stable DNS label so the backend URL doesn't change every deploy.
  DNS_LABEL="${AZURE_DNS_LABEL:-$NAME}"

  # Create or update container instance
  echo "Creating/updating container instance..."
  az container create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NAME" \
    --image "$FULL_IMAGE_NAME" \
    --registry-login-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" \
    --registry-password "$ACR_PASSWORD" \
    --dns-name-label "$DNS_LABEL" \
    --ports 8000 \
    --cpu 1 \
    --memory 1 \
    --environment-variables \
      OPENAI_API_KEY="$OPENAI_API_KEY" \
      OPENAI_MODEL="${OPENAI_MODEL:-gpt-4}" \
      CORS_ALLOW_ORIGINS="${CORS_ALLOW_ORIGINS:-[\"*\"]}" \
    --restart-policy Always \
    --output table

  # Get the FQDN
  FQDN=$(az container show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NAME" \
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
  echo "  az container logs --resource-group $RESOURCE_GROUP --name $NAME --follow"
  echo ""

elif [[ "$TARGET" == "app-service" ]]; then
  echo "=========================================="
  echo "  Deploying to Azure App Service"
  echo "=========================================="
  echo ""
  echo "Resource Group: $RESOURCE_GROUP"
  echo "App Service: $NAME"
  echo "Image: $FULL_IMAGE_NAME"
  echo ""

  APP_SERVICE_PLAN="${NAME}-plan"

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
    --name "$NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --deployment-container-image-name "$FULL_IMAGE_NAME" \
    --output none 2>/dev/null || echo "Web App already exists"

  # Configure container settings
  echo "Configuring container settings..."
  az webapp config container set \
    --name "$NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --docker-custom-image-name "$FULL_IMAGE_NAME" \
    --docker-registry-server-url "https://$ACR_LOGIN_SERVER" \
    --docker-registry-server-user "$ACR_USERNAME" \
    --docker-registry-server-password "$ACR_PASSWORD"

  # Configure app settings
  echo "Configuring app settings..."
  az webapp config appsettings set \
    --name "$NAME" \
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
    --name "$NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --enable-cd true \
    --output none

  # Get the app URL
  APP_URL=$(az webapp show \
    --name "$NAME" \
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
  echo "  az webapp log tail --name $NAME --resource-group $RESOURCE_GROUP"
  echo ""
fi
