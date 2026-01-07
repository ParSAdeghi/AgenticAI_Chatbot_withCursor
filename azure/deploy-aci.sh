#!/usr/bin/env bash
set -euo pipefail

# Deploy to Azure Container Instances
# Usage: ./azure/deploy-aci.sh <resource-group> <acr-name> [container-name]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional local-only config file (DO NOT COMMIT secrets)
for f in "$SCRIPT_DIR/.env.azure" "$SCRIPT_DIR/env.azure"; do
  if [[ -f "$f" ]]; then
    echo "[deploy-aci] Loading Azure config from: $f"
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    break
  fi
done

RESOURCE_GROUP="${1:-${AZURE_RESOURCE_GROUP:-canada-agent-rg}}"
ACR_NAME="${2:-${AZURE_ACR_NAME:-canadaagent}}"
CONTAINER_NAME="${3:-canada-agent-backend}"
IMAGE_NAME="canada-agent-backend"
IMAGE_TAG="${4:-${AZURE_IMAGE_TAG:-latest}}"

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

# Use a stable DNS label so the backend URL doesn't change every deploy.
# If the default label is taken, set AZURE_DNS_LABEL in azure/env.azure.
DNS_LABEL="${AZURE_DNS_LABEL:-$CONTAINER_NAME}"

# Create or update container instance
echo "Creating/updating container instance..."
az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_NAME" \
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
