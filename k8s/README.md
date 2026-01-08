# Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Canada Tourist Chatbot to Kubernetes clusters.

## Deployment Options

### 1. Local Kubernetes (Docker Desktop)
For local testing and development.

### 2. Azure Kubernetes Service (AKS)
For production deployment on Azure.

---

## Quick Start

### Local Deployment (Docker Desktop)

**Prerequisites:**
- Docker Desktop with Kubernetes enabled
- kubectl installed

**Steps:**

1. **Create secret** (first time only):
```bash
kubectl create namespace canada-tourist
kubectl create secret generic canada-tourist-secret \
  --from-literal=OPENAI_API_KEY=sk-your-actual-key-here \
  -n canada-tourist
```

2. **Deploy:**
```bash
./k8s/deploy-local.sh
```

3. **Access the application:**
```bash
# In separate terminals:
kubectl port-forward -n canada-tourist svc/backend 8000:8000
kubectl port-forward -n canada-tourist svc/frontend 3000:80
```

Then open: http://localhost:3000

### Azure Kubernetes Service (AKS)

**Prerequisites:**
- Azure CLI installed and logged in
- kubectl installed
- Backend and frontend images pushed to ACR

**Steps:**

1. **Build and push images** (if not already done):
```bash
./azure/build-backend.sh canada-agent-rg canadaagent latest
./azure/build-frontend.sh canada-agent-rg canadaagent latest http://backend:8000
```

2. **Deploy to AKS:**
```bash
export OPENAI_API_KEY="sk-your-key-here"
./azure/deploy-aks.sh canada-agent-rg canadaagent canada-aks
```

This will:
- Create AKS cluster (if not exists)
- Attach ACR to AKS
- Deploy backend and frontend
- Create LoadBalancer service for frontend

3. **Get frontend URL:**
```bash
kubectl get svc frontend -n canada-tourist
```

---

## Manifest Files

### Core Resources
- `namespace.yaml` - Creates canada-tourist namespace
- `configmap.yaml` - Non-sensitive configuration (models, CORS)
- `secret.yaml.example` - Template for API keys (copy to secret.yaml)

### Backend
- `backend-deployment.yaml` - Backend pods (2 replicas)
- `backend-service.yaml` - Backend ClusterIP service

### Frontend
- `frontend-deployment.yaml` - Frontend pods (2 replicas)
- `frontend-service.yaml` - Frontend LoadBalancer service

### Optional
- `ingress.yaml` - Ingress controller (for custom domains)

---

## Configuration

### Secrets (Required)
Create `k8s/secret.yaml` from the example:

```bash
cp k8s/secret.yaml.example k8s/secret.yaml
# Edit and fill in your OPENAI_API_KEY
kubectl apply -f k8s/secret.yaml
```

Or create via kubectl:
```bash
kubectl create secret generic canada-tourist-secret \
  --from-literal=OPENAI_API_KEY=sk-your-key-here \
  -n canada-tourist
```

### ConfigMap (Optional)
Edit `k8s/configmap.yaml` to change:
- OpenAI models
- CORS origins
- Other non-sensitive config

Then apply:
```bash
kubectl apply -f k8s/configmap.yaml
kubectl rollout restart deployment/backend -n canada-tourist
```

---

## Scaling

### Manual Scaling
```bash
# Scale backend
kubectl scale deployment backend --replicas=3 -n canada-tourist

# Scale frontend
kubectl scale deployment frontend --replicas=3 -n canada-tourist
```

### Auto-Scaling (HPA)
```bash
# Enable metrics server (if not already)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create horizontal pod autoscaler
kubectl autoscale deployment backend \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n canada-tourist

kubectl autoscale deployment frontend \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n canada-tourist
```

---

## Monitoring

### View Logs
```bash
# Backend logs
kubectl logs -f -n canada-tourist -l app=backend

# Frontend logs
kubectl logs -f -n canada-tourist -l app=frontend

# Specific pod
kubectl logs -f -n canada-tourist <pod-name>
```

### Check Status
```bash
# All resources
kubectl get all -n canada-tourist

# Deployments
kubectl get deployments -n canada-tourist

# Pods
kubectl get pods -n canada-tourist -o wide

# Services
kubectl get services -n canada-tourist
```

### Describe Resources
```bash
# Pod details
kubectl describe pod <pod-name> -n canada-tourist

# Deployment details
kubectl describe deployment backend -n canada-tourist
```

---

## Troubleshooting

### Pods not starting
```bash
# Check pod events
kubectl describe pod <pod-name> -n canada-tourist

# Check logs
kubectl logs <pod-name> -n canada-tourist

# Common issues:
# - Image pull errors: Check ACR is attached to AKS
# - CrashLoopBackOff: Check environment variables and secrets
```

### Can't access services
```bash
# Check services
kubectl get svc -n canada-tourist

# For local: use port-forward
kubectl port-forward -n canada-tourist svc/frontend 3000:80

# For AKS: wait for LoadBalancer IP
kubectl get svc frontend -n canada-tourist -w
```

### Update images
```bash
# After pushing new images to ACR, force rollout
kubectl rollout restart deployment/backend -n canada-tourist
kubectl rollout restart deployment/frontend -n canada-tourist

# Check rollout status
kubectl rollout status deployment/backend -n canada-tourist
```

---

## Cleanup

### Delete deployment
```bash
kubectl delete namespace canada-tourist
```

### Delete AKS cluster (Azure)
```bash
az aks delete \
  --resource-group canada-agent-rg \
  --name canada-aks \
  --yes --no-wait
```

---

## Production Considerations

### Security
- Use Azure Key Vault for secrets (integrate with AKS)
- Enable RBAC and pod security policies
- Use network policies to restrict pod communication
- Enable Azure Policy for AKS

### High Availability
- Use multiple node pools across availability zones
- Set pod disruption budgets
- Configure resource requests/limits properly

### Monitoring
- Enable Azure Monitor for containers
- Set up Application Insights
- Configure log analytics workspace

### Cost Optimization
- Use spot instances for non-critical workloads
- Configure cluster autoscaler
- Right-size node pools and pod resources

---

## Comparison: ACI vs AKS

| Feature | ACI | AKS |
|---------|-----|-----|
| **Cost** | Pay per container | Pay for VMs + orchestration |
| **Scaling** | Manual | Auto-scaling, HPA |
| **Complexity** | Simple | More complex |
| **Use Case** | Simple apps, batch jobs | Complex microservices |
| **Management** | Minimal | Full Kubernetes features |

**Recommendation:** Use ACI for simple deployments, AKS when you need orchestration, scaling, and advanced features.
