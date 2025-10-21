# 🚀 Davtro Website - ArgoCD + K8s + GitHub Actions

## 📋 Opis projektu
Kompletne rozwiązanie CI/CD z pełnym stackiem technologicznym.

## 🚀 Szybki start

### 1. Konfiguracja GHCR Secret
```bash
./setup-ghcr-secret.sh USERNAME GH_TOKEN
```

### 2. Deploy ArgoCD
```bash
kubectl apply -f argocd/application.yaml
```

## 🔐 Rozwiązanie problemu 401 Unauthorized
Skrypt automatycznie konfiguruje ServiceAccount z imagePullSecrets dla ArgoCD.
