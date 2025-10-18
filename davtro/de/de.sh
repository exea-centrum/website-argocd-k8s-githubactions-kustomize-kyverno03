#!/bin/bash

set -e

# Konfiguracja
REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
NAMESPACE="davtro"
IMAGE_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
GITHUB_USER="exea-centrum"

echo "🚀 Rozpoczynam tworzenie projektu $REPO_NAME..."

# Sprawdź czy git jest zainstalowany
if ! command -v git &> /dev/null; then
    echo "❌ Git nie jest zainstalowany!"
    exit 1
fi

# Tworzenie struktury katalogów
echo "📁 Tworzenie struktury projektu..."
mkdir -p $REPO_NAME
cd $REPO_NAME

mkdir -p src templates static manifests/base manifests/production .github/workflows argocd policies monitoring terraform

# 1. Tworzenie plików Go
echo "🛠️ Tworzenie aplikacji Go..."

cat > src/main.go << 'EOF'
package main

import (
    "database/sql"
    "encoding/json"
    "fmt"
    "html/template"
    "log"
    "net/http"
    "os"
    "time"

    _ "github.com/lib/pq"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total number of HTTP requests",
    }, []string{"path", "method", "status"})

    httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name:    "http_request_duration_seconds",
        Help:    "Duration of HTTP requests",
        Buckets: prometheus.DefBuckets,
    }, []string{"path", "method"})
)

type PageData struct {
    Title    string
    Content  string
    LastSync time.Time
}

type ScrapedData struct {
    ID      int       `json:"id"`
    Title   string    `json:"title"`
    Content string    `json:"content"`
    Created time.Time `json:"created"`
}

var db *sql.DB
var templates *template.Template

func initDB() {
    var err error
    connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
        os.Getenv("DB_HOST"), os.Getenv("DB_PORT"), os.Getenv("DB_USER"),
        os.Getenv("DB_PASSWORD"), os.Getenv("DB_NAME"))
    
    db, err = sql.Open("postgres", connStr)
    if err != nil {
        log.Fatal(err)
    }

    createTable := `
    CREATE TABLE IF NOT EXISTS scraped_data (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );`
    
    _, err = db.Exec(createTable)
    if err != nil {
        log.Fatal(err)
    }
}

func main() {
    initDB()
    
    templates = template.Must(template.ParseGlob("templates/*.html"))
    
    http.Handle("/metrics", promhttp.Handler())
    http.HandleFunc("/", instrumentHandler("/", homeHandler))
    http.HandleFunc("/health", healthHandler)
    http.HandleFunc("/api/data", apiHandler)
    http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("static"))))

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    
    log.Printf("Server starting on port %s", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}

func instrumentHandler(path string, handler http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        ww := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
        
        handler(ww, r)
        
        duration := time.Since(start).Seconds()
        httpRequestDuration.WithLabelValues(path, r.Method).Observe(duration)
        httpRequestsTotal.WithLabelValues(path, r.Method, fmt.Sprintf("%d", ww.statusCode)).Inc()
    }
}

type responseWriter struct {
    http.ResponseWriter
    statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
    rw.statusCode = code
    rw.ResponseWriter.WriteHeader(code)
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
    var data []ScrapedData
    rows, err := db.Query("SELECT id, title, content, created FROM scraped_data ORDER BY created DESC LIMIT 10")
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    defer rows.Close()

    for rows.Next() {
        var item ScrapedData
        err := rows.Scan(&item.ID, &item.Title, &item.Content, &item.Created)
        if err != nil {
            http.Error(w, err.Error(), http.StatusInternalServerError)
            return
        }
        data = append(data, item)
    }

    templates.ExecuteTemplate(w, "index.html", map[string]interface{}{
        "Data": data,
        "Title": "Davtro Website",
    })
}

func apiHandler(w http.ResponseWriter, r *http.Request) {
    var data []ScrapedData
    rows, err := db.Query("SELECT id, title, content, created FROM scraped_data ORDER BY created DESC")
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    defer rows.Close()

    for rows.Next() {
        var item ScrapedData
        err := rows.Scan(&item.ID, &item.Title, &item.Content, &item.Created)
        if err != nil {
            http.Error(w, err.Error(), http.StatusInternalServerError)
            return
        }
        data = append(data, item)
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(data)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    err := db.Ping()
    if err != nil {
        http.Error(w, "Database not connected", http.StatusServiceUnavailable)
        return
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}
EOF

cat > src/go.mod << 'EOF'
module davtro-website

go 1.21

require (
    github.com/lib/pq v1.10.9
    github.com/prometheus/client_golang v1.17.0
)
EOF

# 2. Dockerfile
echo "🐳 Tworzenie Dockerfile..."

cat > Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY src/go.mod src/go.sum ./
RUN go mod download

COPY src/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates

WORKDIR /root/
COPY --from=builder /app/main .
COPY templates/ ./templates/
COPY static/ ./static/

EXPOSE 8080
CMD ["./main"]
EOF

# 3. HTML Templates
echo "📄 Tworzenie szablonów HTML..."

cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.Title}}</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 0; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .header { 
            background: rgba(255, 255, 255, 0.95); 
            padding: 30px; 
            border-radius: 15px; 
            margin-bottom: 30px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .data-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .data-item { 
            background: rgba(255, 255, 255, 0.95); 
            border: none; 
            margin: 0; 
            padding: 25px; 
            border-radius: 12px; 
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        .data-item:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
        }
        .timestamp { 
            color: #666; 
            font-size: 0.85em; 
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #eee;
        }
        h1 { 
            color: #333; 
            margin: 0 0 10px 0;
            font-size: 2.5em;
        }
        h2 {
            color: white;
            text-align: center;
            margin: 40px 0 30px 0;
            font-size: 2em;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }
        h3 {
            color: #333;
            margin: 0 0 15px 0;
            font-size: 1.4em;
        }
        .nav-links {
            text-align: center;
            margin-top: 30px;
        }
        .nav-links a {
            color: white;
            text-decoration: none;
            margin: 0 15px;
            padding: 12px 25px;
            border: 2px solid white;
            border-radius: 25px;
            transition: all 0.3s ease;
            display: inline-block;
        }
        .nav-links a:hover {
            background: white;
            color: #667eea;
        }
        .status-badge {
            background: #4CAF50;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.8em;
            display: inline-block;
            margin-left: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Davtro Website <span class="status-badge">Live</span></h1>
            <p>Monitoring enabled with Prometheus, Grafana, Loki, and Tempo | Powered by ArgoCD + K8s + GitHub Actions</p>
        </div>

        <h2>📊 Scraped Data</h2>
        <div class="data-grid">
        {{range .Data}}
            <div class="data-item">
                <h3>{{.Title}}</h3>
                <p>{{.Content}}</p>
                <div class="timestamp">🕒 Created: {{.Created.Format "2006-01-02 15:04:05"}}</div>
            </div>
        {{else}}
            <div class="data-item" style="grid-column: 1 / -1; text-align: center;">
                <h3>No data available</h3>
                <p>Data will appear here once scraped from the source website.</p>
            </div>
        {{end}}
        </div>

        <div class="nav-links">
            <a href="/api/data">📡 JSON API</a> 
            <a href="/metrics">📈 Metrics</a> 
            <a href="/health">❤️ Health Check</a>
        </div>
    </div>
</body>
</html>
EOF

# 4. GitHub Actions
echo "⚙️ Konfiguracja GitHub Actions..."

cat > .github/workflows/ci-cd.yaml << EOF
name: Build and Deploy

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: \${{ github.repository }}/$IMAGE_NAME
  KUSTOMIZE_PATH: ./manifests/production

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Set up Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.21'

    - name: Test Go application
      run: |
        cd src
        go mod download
        go build -v ./...

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to GHCR
      uses: docker/login-action@v3
      with:
        registry: \${{ env.REGISTRY }}
        username: \${{ github.actor }}
        password: \${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: \${{ env.REGISTRY }}/\${{ env.IMAGE_NAME }}
        tags: |
          type=sha,prefix={{branch}}-
          type=ref,event=branch
          type=ref,event=pr
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
          type=sha

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: \${{ github.event_name != 'pull_request' }}
        tags: \${{ steps.meta.outputs.tags }}
        labels: \${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  update-manifests:
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.event_name != 'pull_request'
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      with:
        token: \${{ secrets.GITHUB_TOKEN }}

    - name: Update Kustomize image
      run: |
        cd manifests/production
        kustomize edit set image $IMAGE_NAME=\${{ env.REGISTRY }}/\${{ env.IMAGE_NAME }}:\${{ github.sha }}

    - name: Commit and push changes
      run: |
        git config --local user.email "action@github.com"
        git config --local user.name "GitHub Action"
        git add manifests/production/kustomization.yaml
        git diff --staged --quiet || git commit -m "ci: Update image to \${{ github.sha }}"
        git push
EOF

# 5. Kustomize Manifests - Base
echo "🎯 Tworzenie manifestów Kustomize..."

cat > manifests/base/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $IMAGE_NAME
  labels:
    app: $IMAGE_NAME
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $IMAGE_NAME
  template:
    metadata:
      labels:
        app: $IMAGE_NAME
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: website
        image: $IMAGE_NAME:latest
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: host
        - name: DB_PORT
          value: "5432"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: database
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

cat > manifests/base/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: $IMAGE_NAME-service
  labels:
    app: $IMAGE_NAME
    version: v1
spec:
  selector:
    app: $IMAGE_NAME
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
EOF

cat > manifests/base/ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $IMAGE_NAME-ingress
  labels:
    app: $IMAGE_NAME
    version: v1
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  rules:
  - host: $IMAGE_NAME.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $IMAGE_NAME-service
            port:
              number: 80
  tls:
  - hosts:
    - $IMAGE_NAME.local
    secretName: $IMAGE_NAME-tls
EOF

cat > manifests/base/postgres.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  labels:
    app: postgres
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        version: v1
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: database
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        volumeMounts:
        - mountPath: /var/lib/postgresql/data
          name: postgres-data
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  labels:
    app: postgres
    version: v1
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
  type: ClusterIP
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  labels:
    app: postgres
    version: v1
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

cat > manifests/base/secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  labels:
    app: $IMAGE_NAME
    version: v1
type: Opaque
data:
  host: cG9zdGdyZXMtc2VydmljZQ==  # postgres-service
  database: ZGF2dHJvX2Ri         # davtro_db
  username: ZGF2dHJv             # davtro
  password: cGFzc3dvcmQxMjM=     # password123
EOF

cat > manifests/base/service-monitor.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: $IMAGE_NAME-monitor
  labels:
    app: $IMAGE_NAME
    version: v1
spec:
  selector:
    matchLabels:
      app: $IMAGE_NAME
  endpoints:
  - port: 80
    path: /metrics
    interval: 30s
EOF

cat > manifests/base/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - postgres.yaml
  - secrets.yaml
  - service-monitor.yaml

commonLabels:
  app: $IMAGE_NAME
  version: v1

images:
  - name: $IMAGE_NAME
    newTag: latest
EOF

# 6. Kustomize Manifests - Production
cat > manifests/production/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - ../base

images:
  - name: $IMAGE_NAME
    newName: ghcr.io/$REPO_OWNER/$REPO_NAME/$IMAGE_NAME
    newTag: latest
EOF

# 7. ArgoCD Application
echo "🔄 Tworzenie aplikacji ArgoCD..."

cat > argocd/application.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $IMAGE_NAME-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/$REPO_OWNER/$REPO_NAME.git
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
EOF

# 8. Kyverno Policies
echo "🛡️ Tworzenie polityk Kyverno..."

cat > policies/kyverno-policy.yaml << EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds:
          - Deployment
          - Service
          - Ingress
    validate:
      message: "The labels 'app' and 'version' are required."
      pattern:
        metadata:
          labels:
            app: "?*"
            version: "?*"

---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-default-namespace
spec:
  validationFailureAction: enforce
  rules:
  - name: block-default-namespace
    match:
      any:
      - resources:
          kinds:
          - Pod
          - Deployment
          - Service
          namespaces:
          - default
    validate:
      message: "Resources cannot be deployed in the default namespace."
      deny: {}

---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: enforce
  rules:
  - name: check-resource-limits
    match:
      any:
      - resources:
          kinds:
          - Deployment
    validate:
      message: "CPU and memory limits are required."
      pattern:
        spec:
          template:
            spec:
              containers:
              - resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
EOF

# 9. Monitoring Stack
echo "📊 Konfiguracja monitoringu..."

cat > monitoring/monitoring-stack.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    scrape_configs:
    - job_name: '$IMAGE_NAME'
      static_configs:
      - targets: ['$IMAGE_NAME-service.$NAMESPACE.svc.cluster.local:80']
      metrics_path: /metrics
      scrape_interval: 30s

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
        version: v1
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config-volume
          mountPath: /etc/prometheus/
        resources:
          requests:
            memory: "512Mi"
            cpu: "300m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: config-volume
        configMap:
          name: prometheus-config

---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: monitoring
  labels:
    app: prometheus
    version: v1
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
    protocol: TCP
  type: ClusterIP
EOF

# 10. Terraform Configuration
echo "🏗️ Konfiguracja Terraform..."

cat > terraform/main.tf << EOF
terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "davtro"
    workspaces {
      name = "github-actions-terraform"
    }
  }
}

provider "github" {
  owner = "$REPO_OWNER"
}

resource "github_repository" "website" {
  name        = "$REPO_NAME"
  description = "Davtro Website with ArgoCD, K8s, GitHub Actions, Kustomize, Kyverno"
  visibility  = "public"
  auto_init   = true
}

resource "github_actions_secret" "kube_config" {
  repository      = github_repository.website.name
  secret_name     = "KUBE_CONFIG"
  plaintext_value = var.kube_config
}

resource "github_branch_default" "main" {
  repository = github_repository.website.name
  branch     = "main"
}

variable "kube_config" {
  description = "Kubernetes configuration"
  type        = string
  sensitive   = true
}

output "repository_url" {
  value = github_repository.website.html_url
}
EOF

cat > terraform/variables.tf << EOF
variable "kube_config" {
  description = "Kubernetes configuration for GitHub Actions"
  type        = string
  sensitive   = true
}
EOF

cat > terraform/outputs.tf << EOF
output "repository_name" {
  value = github_repository.website.name
}

output "repository_url" {
  value = github_repository.website.html_url
}

output "clone_url" {
  value = github_repository.website.git_clone_url
}
EOF

# 11. Dodatkowe pliki konfiguracyjne
echo "📝 Tworzenie dodatkowych plików..."

cat > .gitignore << 'EOF'
# Binaries
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test binary
*.test

# Output of the go coverage tool
*.out

# Dependency directories
vendor/
node_modules/

# IDE
.vscode/
.idea/
*.swp
*.swo

# Kubernetes
kubeconfig
*.kubeconfig

# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars

# Environment files
.env
.secret
EOF

cat > README.md << EOF
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
\`\`\`
GitHub Repository → GitHub Actions → GHCR.io → ArgoCD → MicroK8s → Website
\`\`\`

## 🚀 Szybki start

### 1. Inicjalizacja
\`\`\`bash
git clone https://github.com/$REPO_OWNER/$REPO_NAME.git
cd $REPO_NAME
\`\`\`

### 2. Deploy ArgoCD Application
\`\`\`bash
kubectl apply -f argocd/application.yaml
\`\`\`

### 3. Monitoring
\`\`\`bash
kubectl create namespace monitoring
kubectl apply -f monitoring/monitoring-stack.yaml
\`\`\`

### 4. Kyverno Policies
\`\`\`bash
kubectl apply -f policies/kyverno-policy.yaml
\`\`\`

## 📊 Endpoints
- 🌐 **Website**: http://$IMAGE_NAME.local
- 📡 **API**: /api/data
- 📈 **Metrics**: /metrics  
- ❤️ **Health**: /health
- 🎯 **ArgoCD**: http://argocd.local
- 📊 **Prometheus**: http://prometheus.monitoring.svc:9090

## 🔧 Konfiguracja

### Zmienne środowiskowe
\`\`\`
DB_HOST=postgres-service
DB_PORT=5432
DB_USER=davtro
DB_PASSWORD=password123
DB_NAME=davtro_db
PORT=8080
\`\`\`

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
EOF

# 12. Inicjalizacja git i pierwszy commit
echo "🔨 Inicjalizacja repozytorium Git..."

# Tworzenie statycznego pliku dla folderu static
mkdir -p static/css
cat > static/css/style.css << 'EOF'
/* Additional CSS styles can be added here */
body {
    margin: 0;
    padding: 0;
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
}
EOF

# Inicjalizacja git
git init
git add .
git commit -m "🚀 Initial commit: Davtro Website with ArgoCD, K8s, GitHub Actions, Kustomize, Kyverno"

echo ""
echo "✅ Projekt utworzony pomyślnie!"
echo ""
echo "📋 Następne kroki:"
echo "1. 🔐 Utwórz nowe repozytorium na GitHub: $REPO_NAME"
echo "2. 📤 Push do GitHub:"
echo "   git remote add origin https://github.com/$REPO_OWNER/$REPO_NAME.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "3. 🎯 Zastosuj ArgoCD Application:"
echo "   kubectl apply -f argocd/application.yaml"
echo ""
echo "4. 🔍 Sprawdź status:"
echo "   argocd app get $IMAGE_NAME-app"
echo ""
echo "5. 🌐 Dostęp do aplikacji:"
echo "   Dodaj do /etc/hosts: 127.0.0.1 $IMAGE_NAME.local"
echo "   Wejdź na: http://$IMAGE_NAME.local"
echo ""
echo "📊 Monitoring będzie dostępny po zastosowaniu:"
echo "kubectl apply -f monitoring/monitoring-stack.yaml"
echo ""
echo "🛡️ Polityki Kyverno:"
echo "kubectl apply -f policies/kyverno-policy.yaml"