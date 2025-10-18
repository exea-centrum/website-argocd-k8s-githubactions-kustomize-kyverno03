#!/bin/bash
set -e

# ================================
# Davtro Website - ArgoCD + GHCR + Kustomize setup
# ================================

REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
NAMESPACE="davtrokyverno03"
IMAGE_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
GHCR_IMAGE="ghcr.io/${REPO_OWNER}/${IMAGE_NAME}:latest"

echo "📦 Tworzenie repozytorium ${REPO_NAME}..."
mkdir -p ${REPO_NAME}/{src,manifests/{base,production},.github/workflows,argocd,terraform}

cd ${REPO_NAME}

# ------------------------------
# Go app
# ------------------------------
cat > src/main.go <<'EOF'
package main

import (
    "database/sql"
    "fmt"
    "log"
    "net/http"
    _ "github.com/lib/pq"
    "os"
)

func main(){
    dbURL := os.Getenv("DATABASE_URL")
    db, err := sql.Open("postgres", dbURL)
    if err!=nil { log.Fatalf("db open: %v", err) }
    defer db.Close()

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request){
        var content string
        err := db.QueryRow("SELECT content FROM pages WHERE name=$1","home").Scan(&content)
        if err==sql.ErrNoRows {
            http.Error(w, "No content", 404)
            return
        } else if err!=nil {
            http.Error(w, err.Error(), 500)
            return
        }
        w.Header().Set("Content-Type","text/html; charset=utf-8")
        fmt.Fprintln(w, content)
    })

    port := os.Getenv("PORT")
    if port=="" { port = "8080" }
    log.Printf("listening on :%s", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF

cat > src/go.mod <<EOF
module github.com/${REPO_OWNER}/${REPO_NAME}

go 1.21

require github.com/lib/pq v1.10.6
EOF

# ------------------------------
# Dockerfile
# ------------------------------
cat > Dockerfile <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /src
COPY go.mod .
COPY src/ ./
RUN CGO_ENABLED=0 go build -o /app ./src

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app /app
USER nonroot
ENTRYPOINT ["/app"]
EOF

# ------------------------------
# Kustomize base
# ------------------------------
cat > manifests/base/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml

images:
  - name: KUSTOMIZE_IMAGE_ID
    newName: ${GHCR_IMAGE%:*}
    newTag: latest

commonLabels:
  app: davtro-website
EOF

cat > manifests/base/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtro-website-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davtro-website
  template:
    metadata:
      labels:
        app: davtro-website
    spec:
      containers:
        - name: davtro-website
          image: ${GHCR_IMAGE}
          ports:
            - containerPort: 8080
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: davtro-db-secret
                  key: database_url
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
EOF

cat > manifests/base/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: davtro-website-svc
spec:
  selector:
    app: davtro-website
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
EOF

cat > manifests/base/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-website-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: davtro.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: davtro-website-svc
                port:
                  number: 80
EOF

# ------------------------------
# Kustomize production
# ------------------------------
cat > manifests/production/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - ../base
  - namespace.yaml
images:
  - name: ${GHCR_IMAGE%:*}
    newTag: latest
EOF

cat > manifests/production/namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

# ------------------------------
# ArgoCD Application
# ------------------------------
cat > argocd/application.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-website-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/${REPO_OWNER}/${REPO_NAME}.git'
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# ------------------------------
# GitHub Actions CI
# ------------------------------
cat > .github/workflows/ci.yaml <<EOF
name: CI - Build & Push
on:
  push:
    branches: [ main, master ]

permissions:
  contents: read
  packages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      - name: Log in to GHCR
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: \${{ github.actor }}
          password: \${{ secrets.GHCR_TOKEN }}
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          file: Dockerfile
          push: true
          tags: ${GHCR_IMAGE}
EOF

# ------------------------------
# Terraform scaffold
# ------------------------------
cat > terraform/main.tf <<EOF
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

resource "kubernetes_namespace" "davtro" {
  metadata {
    name = "${NAMESPACE}"
  }
}

resource "kubernetes_secret" "davtro_db" {
  metadata {
    name = "davtro-db-secret"
    namespace = kubernetes_namespace.davtro.metadata[0].name
  }

  data = {
    database_url = var.database_url
  }
}
EOF

cat > terraform/variables.tf <<EOF
variable "kubeconfig" {
  description = "Ścieżka do kubeconfig"
  type = string
}

variable "database_url" {
  description = "URL połączenia do bazy danych PostgreSQL"
  type = string
}
EOF

# ------------------------------
# README
# ------------------------------
cat > README.md <<EOF
# Davtro Website

Repozytorium CI/CD: GHCR + Kustomize + ArgoCD (namespace: ${NAMESPACE})

## Jak użyć

1. Uruchom ten skrypt: \`bash setup_davtro.sh\`
2. Zainicjuj git: \`git init && git add . && git commit -m "Init"\`
3. (opcjonalnie) Dodaj zdalne repo i zrób push
4. Zainstaluj ArgoCD i zaaplikuj: \`kubectl apply -f argocd/application.yaml\`
5. Obserwuj deployment w ArgoCD UI
EOF

echo "✅ Repozytorium '${REPO_NAME}' zostało utworzone lokalnie."
echo "📂 Struktura dostępna w katalogu: $(pwd)"
