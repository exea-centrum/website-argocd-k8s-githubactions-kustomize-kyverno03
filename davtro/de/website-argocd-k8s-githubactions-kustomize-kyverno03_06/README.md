# 🚀 Davtro Website - ArgoCD + K8s + GitHub Actions

## 📋 Opis projektu
Kompletne rozwiązanie strony internetowej z pełnym stackiem technologicznym:
- **Frontend**: Go + HTML/CSS
- **Backend**: Go + PostgreSQL
- **CI/CD**: GitHub Actions + GHCR
- **Deployment**: ArgoCD + Kustomize
- **Orchestration**: Kubernetes (MicroK8s)
- **Monitoring**: Prometheus + Grafana + Loki + Tempo
- **Security**: Kyverno policies
- **Infrastructure**: Terraform

## 🏗️ Architektura
```
GitHub Repository → GitHub Actions → GHCR.io → ArgoCD → MicroK8s → Website
```

## 🚀 Szybki start

### 1. Inicjalizacja
```bash
git clone https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno03.git
cd website-argocd-k8s-githubactions-kustomize-kyverno03
```

### 2. Deploy ArgoCD Application
```bash
kubectl apply -f argocd/application.yaml
```

### 3. Monitoring
```bash
kubectl create namespace monitoring
kubectl apply -f monitoring/monitoring-stack.yaml
```

### 4. Kyverno Policies
```bash
kubectl apply -f policies/kyverno-policy.yaml
```

## 📊 Endpoints
- 🌐 **Website**: http://website-argocd-k8s-githubactions-kustomize-kyverno03.local
- 📡 **API**: /api/data
- 📈 **Metrics**: /metrics  
- ❤️ **Health**: /health
- 🎯 **ArgoCD**: http://argocd.local
- 📊 **Prometheus**: http://prometheus.monitoring.svc:9090

## 🔧 Konfiguracja

### Zmienne środowiskowe
```
DB_HOST=postgres-service
DB_PORT=5432
DB_USER=davtro
DB_PASSWORD=password123
DB_NAME=davtro_db
PORT=8080
```

## 📈 Monitoring
- Prometheus metrics dostępne pod /metrics
- ServiceMonitor dla Prometheus
- Health checks i readiness probes
- Resource limits i requests

## 🛡️ Bezpieczeństwo
- Kyverno policies dla compliance
- Resource limits
- Readiness/liveness probes
- TLS via cert-manager
