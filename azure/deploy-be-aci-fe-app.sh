#!/usr/bin/env bash
set -euo pipefail

# Deploy Backend to ACI + Frontend to App Service (Full Stack)
# Usage: ./azure/deploy-be-aci-fe-app.sh <resource-group> <acr-name> [backend-name] [frontend-name] [image-tag]
#
# Example:
#   ./azure/deploy-be-aci-fe-app.sh canada-agent-rg canadaagent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional local-only config file (DO NOT COMMIT secrets)
for f in "$SCRIPT_DIR/.env.azure" "$SCRIPT_DIR/env.azure"; do
  if [[ -f "$f" ]]; then
    echo "[deploy-full] Loading Azure config from: $f"
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    break
  fi
done

RESOURCE_GROUP="${1:-${AZURE_RESOURCE_GROUP:-canada-agent-rg}}"
ACR_NAME="${2:-${AZURE_ACR_NAME:-canadaagent}}"
BACKEND_NAME="${3:-canada-agent-backend}"
FRONTEND_NAME="${4:-canada-agent-frontend}"
IMAGE_TAG="${5:-${AZURE_IMAGE_TAG:-latest}}"

echo "=========================================="
echo "  Full Stack Deployment"
echo "  Backend: ACI | Frontend: App Service"
echo "=========================================="
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "ACR Name: $ACR_NAME"
echo "Backend Name: $BACKEND_NAME"
echo "Frontend Name: $FRONTEND_NAME"
echo "Image Tag: $IMAGE_TAG"
echo ""

# Step 1: Deploy backend to ACI
echo "=========================================="
echo "  Step 1: Deploying Backend to ACI"
echo "=========================================="
echo ""
"$SCRIPT_DIR/deploy-backend.sh" aci "$RESOURCE_GROUP" "$ACR_NAME" "$BACKEND_NAME" "$IMAGE_TAG"

# Get backend URL from ACI
echo ""
echo "Getting backend URL..."
BACKEND_FQDN=$(az container show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BACKEND_NAME" \
  --query ipAddress.fqdn -o tsv 2>/dev/null || echo "")

if [[ -z "$BACKEND_FQDN" ]]; then
  echo "ERROR: Could not retrieve backend FQDN. Please check the deployment."
  exit 1
fi

BACKEND_URL="http://$BACKEND_FQDN:8000"
echo "Backend URL: $BACKEND_URL"
echo ""

# Step 2: Build frontend image with backend URL
echo "=========================================="
echo "  Step 2: Building Frontend Image"
echo "=========================================="
echo ""
"$SCRIPT_DIR/build-frontend.sh" "$RESOURCE_GROUP" "$ACR_NAME" "$IMAGE_TAG" "$BACKEND_URL"

# Step 3: Deploy frontend to App Service
echo ""
echo "=========================================="
echo "  Step 3: Deploying Frontend to App Service"
echo "=========================================="
echo ""
"$SCRIPT_DIR/deploy-frontend.sh" "$RESOURCE_GROUP" "$ACR_NAME" "$FRONTEND_NAME" "$IMAGE_TAG"

# Get frontend URL
FRONTEND_URL=$(az webapp show \
  --name "$FRONTEND_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query defaultHostName -o tsv 2>/dev/null || echo "")

echo ""
echo "=========================================="
echo "  Full Stack Deployment Complete!"
echo "=========================================="
echo ""
echo "Backend (ACI):"
echo "  $BACKEND_URL"
echo "  API Docs: $BACKEND_URL/docs"
echo ""
echo "Frontend (App Service):"
if [[ -n "$FRONTEND_URL" ]]; then
  echo "  https://$FRONTEND_URL"
else
  echo "  (URL will be available after deployment completes)"
fi
echo ""
