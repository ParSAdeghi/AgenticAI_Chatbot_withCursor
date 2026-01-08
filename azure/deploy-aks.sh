#!/usr/bin/env bash
set -euo pipefail

# Deploy to Azure Kubernetes Service (AKS)
# Usage: ./azure/deploy-aks.sh <resource-group> <acr-name> <aks-cluster-name> [backend-tag] [frontend-tag]
#
# Example:
#   ./azure/deploy-aks.sh canada-agent-rg canadaagent canada-aks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional local-only config file (DO NOT COMMIT secrets)
for f in "$SCRIPT_DIR/.env.azure" "$SCRIPT_DIR/env.azure"; do
  if [[ -f "$f" ]]; then
    echo "[deploy-aks] Loading Azure config from: $f"
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    break
  fi
done

RESOURCE_GROUP="${1:-${AZURE_RESOURCE_GROUP:-canada-agent-rg}}"
ACR_NAME="${2:-${AZURE_ACR_NAME:-canadaagent}}"
AKS_NAME="${3:-${AZURE_AKS_NAME:-canada-aks}}"
BACKEND_TAG="${4:-${AZURE_IMAGE_TAG:-latest}}"
FRONTEND_TAG="${5:-${AZURE_IMAGE_TAG:-latest}}"

echo "=========================================="
echo "  Deploying to Azure Kubernetes Service"
echo "=========================================="
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "ACR Name: $ACR_NAME"
echo "AKS Cluster: $AKS_NAME"
echo "Backend Tag: $BACKEND_TAG"
echo "Frontend Tag: $FRONTEND_TAG"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI not found. Please install it first:"
  echo "  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl not found. Please install it first:"
  echo "  https://kubernetes.io/docs/tasks/tools/"
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
echo "ACR Login Server: $ACR_LOGIN_SERVER"
echo ""

# Create AKS cluster if it doesn't exist
if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" &> /dev/null; then
  echo "Creating AKS cluster (this may take 5-10 minutes)..."
  az aks create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --node-count 2 \
    --node-vm-size Standard_B2s \
    --enable-managed-identity \
    --attach-acr "$ACR_NAME" \
    --generate-ssh-keys \
    --output none
  echo "AKS cluster created."
else
  echo "AKS cluster already exists."
  
  # Ensure AKS is attached to ACR
  echo "Attaching ACR to AKS..."
  az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_NAME" \
    --attach-acr "$ACR_NAME" \
    --output none 2>/dev/null || echo "ACR already attached."
fi

echo ""

# Get AKS credentials
echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --overwrite-existing

echo ""
echo "Current context: $(kubectl config current-context)"
echo ""

# Check if secret exists, or create it
if ! kubectl get secret canada-tourist-secret -n canada-tourist &> /dev/null 2>&1; then
  echo "Creating secret..."
  
  # Try to load from .env file first
  ENV_FILE="$PROJECT_ROOT/.env"
  if [[ -z "${OPENAI_API_KEY:-}" ]] && [[ -f "$ENV_FILE" ]] && grep -q "OPENAI_API_KEY=" "$ENV_FILE"; then
    echo "Loading OPENAI_API_KEY from .env file..."
    OPENAI_API_KEY=$(grep "OPENAI_API_KEY=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r\n')
  fi
  
  # Prompt if still not set
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "Enter your OpenAI API key:"
    read -s OPENAI_API_KEY
    echo ""
  fi
  
  kubectl create namespace canada-tourist --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic canada-tourist-secret \
    --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
    -n canada-tourist
  echo "Secret created."
else
  echo "Secret already exists."
fi

echo ""
echo "Applying Kubernetes manifests..."

# Update image tags in manifests temporarily
BACKEND_IMAGE="$ACR_LOGIN_SERVER/canada-agent-backend:$BACKEND_TAG"
FRONTEND_IMAGE="$ACR_LOGIN_SERVER/canada-agent-frontend:$FRONTEND_TAG"

# Create temporary manifests with ACR images
cat "$PROJECT_ROOT/k8s/namespace.yaml" | kubectl apply -f -
cat "$PROJECT_ROOT/k8s/configmap.yaml" | kubectl apply -f -

# Backend deployment with ACR image
cat "$PROJECT_ROOT/k8s/backend-deployment.yaml" | \
  sed "s|image: canada-agent-backend:latest|image: $BACKEND_IMAGE|g" | \
  sed "s|imagePullPolicy: IfNotPresent|imagePullPolicy: Always|g" | \
  kubectl apply -f -

cat "$PROJECT_ROOT/k8s/backend-service.yaml" | kubectl apply -f -

# Frontend deployment with ACR image
cat "$PROJECT_ROOT/k8s/frontend-deployment.yaml" | \
  sed "s|image: canada-agent-frontend:latest|image: $FRONTEND_IMAGE|g" | \
  sed "s|imagePullPolicy: IfNotPresent|imagePullPolicy: Always|g" | \
  kubectl apply -f -

cat "$PROJECT_ROOT/k8s/frontend-service.yaml" | kubectl apply -f -

echo ""
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=180s \
  deployment/backend deployment/frontend -n canada-tourist || true

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
echo ""
echo "Services:"
kubectl get services -n canada-tourist
echo ""
echo "Pods:"
kubectl get pods -n canada-tourist
echo ""

# Get frontend external IP
echo "Getting frontend LoadBalancer IP (may take a few minutes)..."
FRONTEND_IP=$(kubectl get svc frontend -n canada-tourist -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

if [[ "$FRONTEND_IP" == "pending" || -z "$FRONTEND_IP" ]]; then
  echo "Frontend LoadBalancer IP is still pending. Check with:"
  echo "  kubectl get svc frontend -n canada-tourist -w"
else
  echo ""
  echo "Frontend URL: http://$FRONTEND_IP"
fi

echo ""
echo "To view logs:"
echo "  Backend:  kubectl logs -f -n canada-tourist -l app=backend"
echo "  Frontend: kubectl logs -f -n canada-tourist -l app=frontend"
echo ""
echo "To delete:"
echo "  kubectl delete namespace canada-tourist"
echo ""
