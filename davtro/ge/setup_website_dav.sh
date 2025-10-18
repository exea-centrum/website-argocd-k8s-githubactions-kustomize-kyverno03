#!/bin/bash

# ====================================================================
# Skrypt inicjalizacyjny GitOps dla Davtro Website na MicroK8s
# - Tworzy kompletną strukturę plików do wysłania na GitHub.
# - Wdraża TYLKO definicję aplikacji ArgoCD, która będzie pobierać manifesty
#   z Twojego przyszłego repozytorium GitHub.
# - NIE buduje obrazu lokalnie i NIE usuwa plików po zakończeniu.
# ====================================================================

set -e # Przerwij w przypadku błędu

# --- 1. Konfiguracja i zmienne ---
# Zmień REPO_OWNER na Twoją nazwę użytkownika/organizacji na GitHub!
REPO_OWNER="TWOJA-NAZWA-UŻYTKOWNIKA-LUB-ORGANIZACJA" 
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
NAMESPACE="davtro"
IMAGE_REGISTRY="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
IMAGE_TAG_PLACEHOLDER="latest" # Używamy 'latest' jako znacznika, który GitHub Actions zaktualizuje

echo "🚀 Rozpoczynam LOKALNE tworzenie struktury GitOps dla repozytorium na GitHub..."
echo "Używana przestrzeń nazw: ${NAMESPACE}"
echo "Docelowy rejestr obrazów (zmień właściciela w plikach!): ${IMAGE_REGISTRY}"

# --- 2. Funkcje pomocnicze ---
check_microk8s() {
    echo "🔍 Sprawdzanie statusu MicroK8s..."
    if ! command -v microk8s &> /dev/null; then
        echo "❌ BŁĄD: MicroK8s nie jest zainstalowany. Zainstaluj MicroK8s."
        exit 1
    fi

    if ! microk8s status | grep -q "running"; then
        echo "⚠️ MicroK8s nie jest uruchomione. Próbuję uruchomić (wymagane hasło sudo)..."
        sudo microk8s start
        microk8s status --wait-ready --timeout 60 || { echo "❌ BŁĄD: MicroK8s nie uruchomiło się poprawnie."; exit 1; }
    fi
    echo "✅ MicroK8s działa i jest gotowe."
}

# --- 3. Weryfikacja MicroK8s i dodatków ---
check_microk8s
echo "ℹ️  UWAGA: Musisz ręcznie aktywować dodatek ArgoCD: microk8s enable argocd"
echo "ℹ️  UWAGA: Nie aktywuję dodatków MicroK8s. Zakładam, że ingress, prometheus i grafana są już włączone."

# --- 4. Tworzenie lokalnej struktury katalogów (symulacja repo) ---
echo "📂 Tworzenie lokalnej struktury plików GitOps..."
APP_DIR="${REPO_NAME}"
rm -rf ${APP_DIR} # Wyczyść poprzednie wdrożenia
mkdir -p ${APP_DIR}/src \
         ${APP_DIR}/manifests/base \
         ${APP_DIR}/manifests/production \
         ${APP_DIR}/manifests/argocd \
         ${APP_DIR}/.github/workflows

# --- 5. Generowanie plików aplikacji Go z danymi (BEZ ZMIAN W TREŚCI) ---
echo "📝 Generowanie aplikacji Go (src/main.go) z danymi Davtro Website..."
# --- Dane symulujące zawartość strony Dawida Trojanowskiego ---
MOCKED_CONTENT=$(cat <<'EOF_DATA'
<h2>O Mnie</h2>
<p>Jestem entuzjastą DevOps, specjalizującym się w automatyzacji, konteneryzacji (Docker, Kubernetes) oraz CI/CD. To wdrożenie jest zarządzane przez ArgoCD, które synchronizuje manifesty z repozytorium GitHub.</p>
<h2>Technologie w Użyciu</h2>
<ul>
    <li><strong>Język Backend:</strong> GoLang (z metrykami Prometheus)</li>
    <li><strong>Orkiestracja:</strong> MicroK8s</li>
    <li><strong>Wdrożenie GitOps:</strong> ArgoCD & Kustomize (pobrane z GitHuba)</li>
    <li><strong>CI/CD:</strong> GitHub Actions (budowanie i push obrazu)</li>
    <li><strong>Baza Danych:</strong> PostgreSQL (w osobnym Deployment)</li>
</ul>
EOF_DATA
)

# Wprowadzenie MOCKED_CONTENT do pliku Go
cat <<EOF_GO > ${APP_DIR}/src/main.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Mock dla konfiguracji połączenia z bazą danych
const (
	DB_HOST = "postgres-service"
	DB_PORT = "5432"
	DB_USER = "appuser"
	DB_NAME = "davtrodb"
)

var (
	// Metryki Prometheus
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Liczba zapytań HTTP."},
		[]string{"path", "method", "code"},
	)
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_seconds", Help: "Histogram czasu trwania zapytań HTTP."},
		[]string{"path", "method"},
	)
	// Treść strony pobrana ze wskazanej witryny (zasymulowana)
	pageContent = \`${MOCKED_CONTENT}\`
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	
	dbPassword := os.Getenv("DB_PASSWORD")
	log.Printf("Baza danych: host=%s, user=%s, hasło_status=%t", DB_HOST, DB_USER, dbPassword != "")
	// W tym miejscu w prawdziwej aplikacji nastąpiłoby połączenie z DB

	http.HandleFunc("/", loggingMiddleware(homeHandler))
	http.HandleFunc("/healthz", healthzHandler)
	http.Handle("/metrics", promhttp.Handler())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Serwer nasłuchuje na :%s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Błąd uruchomienia serwera: %v", err)
	}
}

// Handler głównej strony z HTML/CSS i wstrzykniętą treścią
func homeHandler(w http.ResponseWriter, r *http.Request) {
	dbStatus := "Baza Danych: Osiągalna (postgres-service)"
	
	htmlContent := fmt.Sprintf(\`
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Davtro Website - %s</title>
    <style>
        body { font-family: 'Arial', sans-serif; background-color: #f4f7f6; color: #333; margin: 0; padding: 40px; text-align: center; }
        .container { max-width: 800px; margin: 0 auto; background: #ffffff; padding: 30px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1); text-align: left; }
        h1 { color: #0056b3; border-bottom: 3px solid #0056b3; padding-bottom: 10px; margin-bottom: 20px; text-align: center;}
        h2 { color: #007bff; margin-top: 25px; }
        ul { list-style-type: none; padding: 0; }
        li { margin-bottom: 10px; padding: 5px 0; border-bottom: 1px dashed #eee; }
        .status-box { margin-top: 30px; padding: 15px; background-color: #e6f7ff; border-left: 5px solid #007bff; font-size: 0.9em; text-align: left;}
        .status-ok { color: green; font-weight: bold; }
        .status-monitoring { color: orange; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Strona Dawida Trojanowskiego (Wdrożenie GitOps przez ArgoCD)</h1>
        %s
        <div class="status-box">
            <h2>Status Środowiska K8s</h2>
            <p><strong>Aplikacja Go:</strong> <span class="status-ok">Działa</span> (Metrics /metrics)</p>
            <p><strong>PostgreSQL Service:</strong> %s</p>
            <p><strong>Monitoring:</strong> <span class="status-monitoring">Prometheus/Grafana</span> jest aktywny w klastrze.</p>
        </div>
    </div>
</body>
</html>
\`, DB_NAME, pageContent, dbStatus)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(htmlContent))
}

# --- Funkcje pomocnicze do monitoringu (Logging Middleware, Healthz, Wrapper) ---
type responseWriterWrapper struct { http.ResponseWriter; statusCode int }
func (lrw *responseWriterWrapper) WriteHeader(code int) { lrw.statusCode = code; lrw.ResponseWriter.WriteHeader(code) }
func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lw := &responseWriterWrapper{ResponseWriter: w}
		next(lw, r)
		duration := time.Since(start).Seconds()
		path := r.URL.Path
		method := r.Method
		statusCode := fmt.Sprintf("%d", lw.statusCode)
		log.Printf("Zapytanie: %s %s | Status: %s | Czas: %v", method, path, statusCode, duration)
		httpRequestsTotal.WithLabelValues(path, method, statusCode).Inc()
		httpRequestDuration.WithLabelValues(path, method).Observe(duration)
	}
}
func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}
EOF_GO

# Pliki Go i Dockerfile
cat <<EOF_MOD > ${APP_DIR}/go.mod
module ${REPO_OWNER}/${REPO_NAME}
go 1.21
require (
	github.com/prometheus/client_golang v1.17.0
)
EOF_MOD

cat <<EOF_DOCKER > ${APP_DIR}/Dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY src/*.go ./
RUN go build -o /davtro-website ./main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /davtro-website .

EXPOSE 8080
CMD ["./davtro-website"]
EOF_DOCKER
echo "✅ Aplikacja Go i pliki budowania wygenerowane."

# --- 6. Generowanie Manifestów Kustomize (Wymagana zmiana obrazu!) ---
echo "📝 Generowanie manifestów Kustomize..."
# Manifesty Base (Bez zmian w base, ale pliki muszą zostać wygenerowane)
cat <<EOF_PG_DEP > ${APP_DIR}/manifests/base/postgres-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-deployment
  labels: { app: postgres }
spec:
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { app: postgres } }
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          value: appuser
        - name: POSTGRES_DB
          value: davtrodb
        - name: POSTGRES_PASSWORD
          valueFrom: { secretKeyRef: { name: postgres-secret, key: password } }
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        emptyDir: {}
EOF_PG_DEP

cat <<EOF_PG_SVC > ${APP_DIR}/manifests/base/postgres-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  labels: { app: postgres }
spec:
  type: ClusterIP
  selector: { app: postgres }
  ports:
  - port: 5432
    targetPort: 5432
EOF_PG_SVC

cat <<EOF_WEB_DEP > ${APP_DIR}/manifests/base/website-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtro-website-deployment
  labels:
    app: davtro-website-app
spec:
  replicas: 2
  selector: { matchLabels: { app: davtro-website-app } }
  template:
    metadata: { labels: { app: davtro-website-app } }
    spec:
      containers:
      - name: davtro-website-container
        image: ${REPO_NAME}:placeholder # Placeholder do podmiany przez Kustomize
        ports:
        - containerPort: 8080
        resources: { limits: { memory: "128Mi", cpu: "500m" } }
        env:
        - name: DB_PASSWORD
          valueFrom: { secretKeyRef: { name: postgres-secret, key: password } }
        livenessProbe: { httpGet: { path: /healthz, port: 8080 }, initialDelaySeconds: 5 }
        readinessProbe: { httpGet: { path: /healthz, port: 8080 }, initialDelaySeconds: 10 }
EOF_WEB_DEP

cat <<EOF_WEB_SVC > ${APP_DIR}/manifests/base/website-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: davtro-website-service
  labels:
    app: davtro-website-app
    release: prometheus-stack # Wymagane przez Prometheus Operator
spec:
  type: ClusterIP
  selector: { app: davtro-website-app }
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
EOF_WEB_SVC

cat <<EOF_K_BASE > ${APP_DIR}/manifests/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
secretGenerator:
- name: postgres-secret
  literals:
  - password=bardzotajnehaslo123 

resources:
- postgres-deployment.yaml
- postgres-service.yaml
- website-deployment.yaml
- website-service.yaml
EOF_K_BASE

# Manifesty Production (Ingress, ServiceMonitor)
cat <<EOF_NS > ${APP_DIR}/manifests/production/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels: { logging-target: davtro }
EOF_NS

cat <<EOF_ING > ${APP_DIR}/manifests/production/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-website-ingress
  annotations:
    kubernetes.io/ingress.class: nginx 
spec:
  rules:
  - host: davtro.local.exea-centrum.pl 
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: davtro-website-service
            port: { number: 80 }
EOF_ING

cat <<EOF_SM > ${APP_DIR}/manifests/production/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: davtro-website-monitor
  labels: { release: prometheus-stack }
spec:
  selector: { matchLabels: { app: davtro-website-app } }
  namespaceSelector: { matchNames: [ "${NAMESPACE}" ] }
  endpoints:
  - port: http 
    path: /metrics
    interval: 30s
EOF_SM

# Główny Kustomization Production - Zmiana nazwy obrazu na registry
cat <<EOF_K_PROD > ${APP_DIR}/manifests/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
- ../base
- namespace.yaml
- ingress.yaml
- servicemonitor.yaml

# Zmiana obrazu na publiczny/rejestrowy
images:
- name: ${REPO_NAME}:placeholder
  newName: ${IMAGE_REGISTRY}
  newTag: ${IMAGE_TAG_PLACEHOLDER} # Będzie aktualizowane przez GitHub Actions po każdym buildzie

namePrefix:
EOF_K_PROD
echo "✅ Manifesty Kustomize wygenerowane i zaktualizowane dla rejestru."

# --- 7. Generowanie pliku definicji ArgoCD Application ---
REPO_HTTPS_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

cat <<EOF_ARGO_APP > ${APP_DIR}/manifests/argocd/davtro-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davtro-website
  namespace: argocd 
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: default
  source:
    repoURL: ${REPO_HTTPS_URL} # Pamiętaj o zmianie właściciela na Twój!
    targetRevision: HEAD
    path: manifests/production # Ścieżka do głównego kustomization.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF_ARGO_APP

cat <<EOF_K_ARGO > ${APP_DIR}/manifests/argocd/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- davtro-app.yaml
EOF_K_ARGO
echo "✅ Manifest ArgoCD Application wygenerowany. Wskaże na repo: ${REPO_HTTPS_URL}"

# --- 8. Generowanie pliku GitHub Actions (CI/CD) ---
cat <<EOF_GA > ${APP_DIR}/.github/workflows/ci-cd.yaml
name: CI/CD Build & Deploy

on:
  push:
    branches:
      - main
    paths:
      - 'src/**'
      - 'Dockerfile'
      - 'go.mod'

env:
  DOCKER_IMAGE: \${{ secrets.GHCR_REGISTRY }}/\${{ github.repository }}
  KUSTOMIZE_PATH: manifests/production

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4
      
      # Logowanie do GitHub Container Registry
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: \${{ secrets.GHCR_REGISTRY }}
          username: \${{ github.actor }}
          password: \${{ secrets.GITHUB_TOKEN }}
          
      # Ustalanie TAGu na podstawie SHA commitu
      - name: Set Image Tag
        id: set_tag
        run: echo "TAG=\$(echo \${{ github.sha }} | head -c 7)" >> \$GITHUB_OUTPUT

      # Budowanie i push obrazu
      - name: Build and Push Docker Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |\${{ env.DOCKER_IMAGE }}:\${{ steps.set_tag.outputs.TAG }}
                \${{ env.DOCKER_IMAGE }}:\${{ env.IMAGE_TAG_PLACEHOLDER }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Aktualizacja tagu w pliku Kustomize (Automatyzacja ArgoCD)
      - name: Update Image Tag in Kustomize
        uses: karancode/kustomize-image-tag-update@v1
        with:
          kustomize_path: \${{ env.KUSTOMIZE_PATH }}
          image_name: \${{ env.DOCKER_IMAGE }}
          new_tag: \${{ steps.set_tag.outputs.TAG }}

      # Commit i Push zaktualizowanego pliku Kustomize
      - name: Commit and Push Kustomize Update
        uses: EndBug/add-and-commit@v9
        with:
          author_name: github-actions[bot]
          author_email: 41898282+github-actions[bot]@users.noreply.github.com
          message: "GitOps: Update image tag to \${{ steps.set_tag.outputs.TAG }}"
          add: '\${{ env.KUSTOMIZE_PATH }}/kustomization.yaml'
EOF_GA
echo "✅ Plik GitHub Actions wygenerowany."

# --- 9. Wdrożenie Application ArgoCD ---
echo "💾 Wdrożenie pliku ArgoCD Application na MicroK8s (zakładając, że ArgoCD jest włączone)..."
microk8s kubectl apply -k ${APP_DIR}/manifests/argocd
echo "✅ Definicja ArgoCD Application wdrożona."

# --- 10. Instrukcje końcowe ---
echo "================================================================"
echo "                   Proces Inicjalizacji GitOps Zakończony!      "
echo "================================================================="
echo ""
echo "!!! KROK 1: Zmień właściciela repozytorium (REPO_OWNER) w plikach:"
echo "   Edytuj plik: ${APP_DIR}/deploy_davtro.sh (aby mieć poprawną zmienną lokalnie)"
echo "   Oraz plik:   ${APP_DIR}/manifests/argocd/davtro-app.yaml (URL repozytorium)"
echo ""
echo "!!! KROK 2: Utwórz repozytorium na GitHub i wyślij pliki:"
echo "   cd ${APP_DIR}"
echo "   git init"
echo "   git add ."
echo "   git commit -m 'Initial commit of GitOps structure'"
echo "   git remote add origin https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
echo "   git push -u origin main"
echo ""
echo "!!! KROK 3: Upewnij się, że ArgoCD jest włączone w MicroK8s i sprawdź status:"
echo "   microk8s enable argocd"
echo "   microk8s kubectl get app -n argocd"
echo ""
echo "➡️  Gdy tylko wciśniesz pliki na GitHub, GitHub Actions zbuduje obraz, a ArgoCD go wdroży."
echo "================================================================"
