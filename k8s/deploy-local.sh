#!/usr/bin/env bash
set -euo pipefail

# Deploy to Local Kubernetes (Docker Desktop)
# Usage: ./k8s/deploy-local.sh [backend-image-tag] [frontend-image-tag]
#
# Prerequisites:
#   - Docker Desktop with Kubernetes enabled
#   - kubectl installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKEND_IMAGE_TAG="${1:-latest}"
FRONTEND_IMAGE_TAG="${2:-latest}"

echo "=========================================="
echo "  Deploying to Local Kubernetes"
echo "  (Docker Desktop)"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl not found. Please install kubectl first:"
  echo "  https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi

# Check if Kubernetes is running
if ! kubectl cluster-info &> /dev/null; then
  echo "ERROR: Kubernetes cluster not reachable."
  echo "Make sure Docker Desktop Kubernetes is enabled:"
  echo "  Docker Desktop → Settings → Kubernetes → Enable Kubernetes"
  exit 1
fi

echo "Current context: $(kubectl config current-context)"
echo ""

# Build Docker images locally (for Docker Desktop)
echo "Building backend image..."
cd "$PROJECT_ROOT/backend"
docker build -t canada-agent-backend:"$BACKEND_IMAGE_TAG" .

echo ""
echo "Building frontend image..."
cd "$PROJECT_ROOT/frontend"
docker build -t canada-agent-frontend:"$FRONTEND_IMAGE_TAG" \
  --build-arg NEXT_PUBLIC_BACKEND_URL=http://localhost:8000 .

echo ""
echo "Images built successfully."
echo ""

# Check if secret exists, or create it from .env file
if ! kubectl get secret canada-tourist-secret -n canada-tourist &> /dev/null 2>&1; then
  echo "Secret 'canada-tourist-secret' not found. Attempting to create..."
  
  # Try to load OPENAI_API_KEY from .env file
  ENV_FILE="$PROJECT_ROOT/.env"
  if [[ -f "$ENV_FILE" ]] && grep -q "OPENAI_API_KEY=" "$ENV_FILE"; then
    echo "Loading OPENAI_API_KEY from .env file..."
    OPENAI_API_KEY=$(grep "OPENAI_API_KEY=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r\n')
    
    if [[ -n "$OPENAI_API_KEY" && "$OPENAI_API_KEY" != "your-openai-api-key-here" ]]; then
      kubectl create namespace canada-tourist --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
      kubectl create secret generic canada-tourist-secret \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        -n canada-tourist
      echo "✓ Secret created from .env file"
    else
      echo "ERROR: OPENAI_API_KEY in .env is a placeholder. Please set your real API key in .env"
      exit 1
    fi
  else
    echo ""
    echo "⚠ WARNING: Could not find .env file or OPENAI_API_KEY in it."
    echo ""
    echo "Please create the secret manually:"
    echo "  kubectl create secret generic canada-tourist-secret \\"
    echo "    --from-literal=OPENAI_API_KEY=sk-your-key-here \\"
    echo "    -n canada-tourist"
    echo ""
    exit 1
  fi
else
  echo "✓ Secret 'canada-tourist-secret' already exists"
fi

# Apply Kubernetes manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/configmap.yaml"
kubectl apply -f "$SCRIPT_DIR/backend-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/backend-service.yaml"
kubectl apply -f "$SCRIPT_DIR/frontend-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/frontend-service.yaml"

echo ""
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=120s \
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

# Cleanup function for port-forwards
cleanup_k8s() {
  echo ""
  echo "[deploy-local] Stopping port-forwards..."
  if [[ -n "${BACKEND_PF_PID:-}" ]]; then
    kill "$BACKEND_PF_PID" 2>/dev/null || true
  fi
  if [[ -n "${FRONTEND_PF_PID:-}" ]]; then
    kill "$FRONTEND_PF_PID" 2>/dev/null || true
  fi
  echo "[deploy-local] Port-forwards stopped"
  exit 0
}
trap cleanup_k8s EXIT INT TERM

# Start port-forwards automatically
echo "Starting port-forwards..."
kubectl port-forward -n canada-tourist svc/backend 8000:8000 > /tmp/k8s-backend-pf.log 2>&1 &
BACKEND_PF_PID=$!

kubectl port-forward -n canada-tourist svc/frontend 3000:80 > /tmp/k8s-frontend-pf.log 2>&1 &
FRONTEND_PF_PID=$!

# Wait for port-forwards to be ready
sleep 3

# Test connectivity
if curl -s http://localhost:8000/healthz > /dev/null 2>&1; then
  echo "✓ Backend port-forward ready on http://localhost:8000"
else
  echo "⚠ Backend port-forward may still be starting..."
fi

if curl -s http://localhost:3000 > /dev/null 2>&1; then
  echo "✓ Frontend port-forward ready on http://localhost:3000"
else
  echo "⚠ Frontend port-forward may still be starting..."
fi

echo ""
echo "=========================================="
echo "  Application Ready!"
echo "=========================================="
echo ""
echo "Access your application:"
echo "  Frontend: http://localhost:3000"
echo "  Backend:  http://localhost:8000"
echo "  API Docs: http://localhost:8000/docs"
echo ""
echo "Port-forward PIDs:"
echo "  Backend:  $BACKEND_PF_PID"
echo "  Frontend: $FRONTEND_PF_PID"
echo ""
echo "Logs:"
echo "  Backend PF:  tail -f /tmp/k8s-backend-pf.log"
echo "  Frontend PF: tail -f /tmp/k8s-frontend-pf.log"
echo "  Backend:     kubectl logs -f -n canada-tourist -l app=backend"
echo "  Frontend:    kubectl logs -f -n canada-tourist -l app=frontend"
echo ""
echo "Press Ctrl+C to stop port-forwards and exit"
echo "=========================================="
echo ""

# Keep script running and tail logs
tail -f /tmp/k8s-backend-pf.log /tmp/k8s-frontend-pf.log
