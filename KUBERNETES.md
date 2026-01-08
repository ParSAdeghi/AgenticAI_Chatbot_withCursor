# Kubernetes Deployment Guide

This project supports deployment to Kubernetes clusters, both locally (Docker Desktop) and on Azure (AKS).

---

## Architecture

```
Kubernetes Cluster
├── Namespace: canada-tourist
├── ConfigMap: canada-tourist-config (models, CORS)
├── Secret: canada-tourist-secret (OPENAI_API_KEY)
├── Backend Deployment (2 replicas)
│   └── Service (ClusterIP on port 8000)
└── Frontend Deployment (2 replicas)
    └── Service (LoadBalancer on port 80)
```

---

## Quick Start Options

### Option 1: Local Kubernetes (Docker Desktop)

**Best for:** Development and testing

```bash
# 1. Enable Kubernetes in Docker Desktop
# Docker Desktop → Settings → Kubernetes → Enable Kubernetes

# 2. Create secret
kubectl create namespace canada-tourist
kubectl create secret generic canada-tourist-secret \
  --from-literal=OPENAI_API_KEY=sk-your-key-here \
  -n canada-tourist

# 3. Deploy
./k8s/deploy-local.sh

# 4. Access
kubectl port-forward -n canada-tourist svc/frontend 3000:80
# Open: http://localhost:3000
```

### Option 2: Azure Kubernetes Service (AKS)

**Best for:** Production deployment

```bash
# 1. Build and push images to ACR
./azure/build-backend.sh canada-agent-rg canadaagent latest
./azure/build-frontend.sh canada-agent-rg canadaagent latest http://backend:8000

# 2. Deploy to AKS
export OPENAI_API_KEY="sk-your-key-here"
./azure/deploy-aks.sh canada-agent-rg canadaagent canada-aks

# 3. Get frontend URL
kubectl get svc frontend -n canada-tourist
```

---

## Deployment Comparison

| Feature | Local (Docker Desktop) | AKS (Azure) |
|---------|------------------------|-------------|
| **Cost** | Free | Pay for VMs |
| **Scalability** | Limited | Auto-scaling |
| **Use Case** | Dev/Testing | Production |
| **Internet Access** | localhost only | Public LoadBalancer |
| **Setup Time** | 1 minute | 5-10 minutes |

---

## Scripts

### Build Scripts
- `azure/build-backend.sh` - Build backend Docker image
- `azure/build-frontend.sh` - Build frontend Docker image

### Deployment Scripts
- `k8s/deploy-local.sh` - Deploy to Docker Desktop Kubernetes
- `azure/deploy-aks.sh` - Deploy to Azure Kubernetes Service

---

## Kubernetes Manifests

All manifests are in the `k8s/` directory:

| File | Purpose |
|------|---------|
| `namespace.yaml` | Creates canada-tourist namespace |
| `configmap.yaml` | Non-sensitive config (models, CORS) |
| `secret.yaml.example` | Template for API keys |
| `backend-deployment.yaml` | Backend pods (2 replicas) |
| `backend-service.yaml` | Backend ClusterIP service |
| `frontend-deployment.yaml` | Frontend pods (2 replicas) |
| `frontend-service.yaml` | Frontend LoadBalancer service |
| `ingress.yaml` | Ingress controller (optional) |

---

## Common Commands

### Check Status
```bash
kubectl get all -n canada-tourist
kubectl get pods -n canada-tourist
kubectl get services -n canada-tourist
```

### View Logs
```bash
# Backend
kubectl logs -f -n canada-tourist -l app=backend

# Frontend
kubectl logs -f -n canada-tourist -l app=frontend
```

### Scale
```bash
kubectl scale deployment backend --replicas=3 -n canada-tourist
kubectl scale deployment frontend --replicas=3 -n canada-tourist
```

### Update Images
```bash
# After building new images
kubectl rollout restart deployment/backend -n canada-tourist
kubectl rollout restart deployment/frontend -n canada-tourist
```

### Cleanup
```bash
kubectl delete namespace canada-tourist
```

---

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n canada-tourist
kubectl logs <pod-name> -n canada-tourist
```

### Can't access services locally
```bash
# Use port-forward
kubectl port-forward -n canada-tourist svc/backend 8000:8000
kubectl port-forward -n canada-tourist svc/frontend 3000:80
```

### Image pull errors
- **Local:** Make sure images are built locally
- **AKS:** Ensure ACR is attached to AKS cluster

---

For detailed information, see [`k8s/README.md`](k8s/README.md).
