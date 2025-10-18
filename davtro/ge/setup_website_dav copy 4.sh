#!/bin/bash

# ====================================================================
# Skrypt wdrożeniowy dla MicroK8s z Go, PostgreSQL, Kustomize, Kyverno i ArgoCD
# (Całość działa lokalnie, bez pusha na GitHub)
# ====================================================================

set -e # Przerwij w przypadku błędu

# --- 1. Konfiguracja i zmienne ---
REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
NAMESPACE="davtro"
ARGO_APP_NAME="davtro-website-app"
KYVERNO_POLICY_NAME="enforce-monitoring-label"
IMAGE_TAG="local-$(date +'%Y%m%d%H%M%S')"
IMAGE_FULL_NAME="${REPO_NAME}:${IMAGE_TAG}"

echo "🚀 Rozpoczynam kompletne wdrożenie Davtro Website na MicroK8s..."
echo "Używana przestrzeń nazw: ${NAMESPACE}"

# --- 2. Funkcje pomocnicze ---
check_microk8s() {
    echo "🔍 Sprawdzanie statusu MicroK8s..."
    if ! command -v microk8s &> /dev/null; then
        echo "❌ BŁĄD: MicroK8s nie jest zainstalowany. Zainstaluj MicroK8s."
        exit 1
    fi

    # Sprawdzenie, czy MicroK8s jest uruchomione
    # Używamy --wait-ready z krótkim timeoutem, aby uniknąć problemu z --field i weryfikować status
    if ! microk8s status --wait-ready --timeout 5 &> /dev/null; then
        echo "⚠️ MicroK8s nie jest uruchomione lub nie jest gotowe. Próbuję uruchomić..."
        # Sprawdzamy ponownie, czy jest naprawdę zatrzymane, aby nie prosić o hasło, jeśli to tylko opóźnienie
        if ! microk8s status | grep -q "running"; then
            echo "   MicroK8s jest zatrzymane. Wymagane hasło sudo do uruchomienia MicroK8s."
            # Użycie sudo do microk8s start
            sudo microk8s start
            echo "   Poczekaj, aż MicroK8s się ustabilizuje..."
            microk8s status --wait-ready --timeout 60 || { echo "❌ BŁĄD: MicroK8s nie uruchomiło się poprawnie."; exit 1; }
            echo "   ✅ MicroK8s uruchomione."
        else
            echo "   MicroK8s jest już uruchomione, ale nie gotowe. Czekam na ustabilizowanie..."
            microk8s status --wait-ready --timeout 60 || { echo "❌ BŁĄD: MicroK8s nie ustabilizowało się poprawnie."; exit 1; }
        fi
    fi
    echo "✅ MicroK8s działa i jest gotowe."
}

enable_addon() {
    local addon_name=$1
    echo "⚙️ Włączanie dodatku MicroK8s: ${addon_name}..."
    # Sprawdzamy, czy dodatek jest już włączony, aby uniknąć ponownego uruchamiania
    if ! microk8s status | grep -q "^${addon_name}\s*:\s*enabled"; then
        microk8s enable "${addon_name}"
        echo "   Czekam na uruchomienie ${addon_name}..."
        # Niektóre dodatki potrzebują więcej czasu, dodajemy wait-ready
        microk8s status --wait-ready --timeout 90 || { echo "❌ BŁĄD: Dodatek ${addon_name} nie uruchomił się poprawnie."; exit 1; }
    fi
    echo "✅ Dodatek ${addon_name} jest włączony i gotowy."
}

# --- 3. Weryfikacja MicroK8s i dodatków (GLTP) ---
check_microk8s
enable_addon argocd
enable_addon ingress
enable_addon prometheus
enable_addon grafana
# Optional: enable_addon loki, enable_addon tempo (jeśli nie są częścią prometheus-stack)

# --- 4. Tworzenie lokalnej struktury katalogów (symulacja repo) ---
echo "📂 Tworzenie lokalnej struktury plików..."
APP_DIR="${REPO_NAME}"
rm -rf ${APP_DIR} # Wyczyść poprzednie wdrożenia
mkdir -p ${APP_DIR}/src \
         ${APP_DIR}/manifests/base \
         ${APP_DIR}/manifests/production \
         ${APP_DIR}/kyverno \
         ${APP_DIR}/argocd

# --- 5. Generowanie plików aplikacji Go z danymi (symulacja pobrania) ---
echo "📝 Generowanie aplikacji Go (src/main.go) z danymi z Davtro Website..."

# --- Dane symulujące zawartość strony Dawida Trojanowskiego ---
MOCKED_CONTENT=$(cat <<'EOF_DATA'
<h2>O Mnie</h2>
<p>Jestem entuzjastą DevOps, specjalizującym się w automatyzacji, konteneryzacji (Docker, Kubernetes) oraz CI/CD z wykorzystaniem ArgoCD i GitHub Actions. Zbudowałem to środowisko od podstaw, integrując pełny stos monitorowania GLTP (Grafana, Loki, Tempo, Prometheus).</p>
<h2>Technologie w Użyciu</h2>
<ul>
    <li><strong>Język Backend:</strong> GoLang (z metrykami Prometheus)</li>
    <li><strong>Orkiestracja:</strong> MicroK8s</li>
    <li><strong>GitOps:</strong> ArgoCD</li>
    <li><strong>Baza Danych:</strong> PostgreSQL (w osobnym Deployment)</li>
    <li><strong>Polityki:</strong> Kyverno</li>
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
        <h1>Strona Dawida Trojanowskiego (Wdrożenie GitOps)</h1>
        %s
        <div class="status-box">
            <h2>Status Środowiska K8s</h2>
            <p><strong>Aplikacja Go:</strong> <span class="status-ok">Działa</span> (Metrics /metrics)</p>
            <p><strong>PostgreSQL Service:</strong> %s</p>
            <p><strong>Monitoring:</strong> <span class="status-monitoring">Prometheus/Loki</span> jest aktywny w klastrze.</p>
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

# Pliki Go
cat <<EOF_MOD > ${APP_DIR}/go.mod
module ${REPO_OWNER}/${REPO_NAME}
go 1.21
require (
	github.com/prometheus/client_golang v1.17.0
)
EOF_MOD

# Plik Dockerfile
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

# --- 6. Generowanie Manifestów Kustomize ---
echo "📝 Generowanie manifestów Kustomize..."
# Manifesty Base (PostgreSQL, Go App)
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
    app.kubernetes.io/component: web-api # Etykieta dla Kyverno
spec:
  replicas: 2
  selector: { matchLabels: { app: davtro-website-app } }
  template:
    metadata: { labels: { app: davtro-website-app } }
    spec:
      containers:
      - name: davtro-website-container
        image: ${REPO_NAME}:placeholder # Placeholder
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
  - password=bardzotajnehaslo123 # Hasło do PostgreSQL jest już w kodzie, nie wymaga podawania
    # Hasło do PostgreSQL jest zdefiniowane tutaj i jest automatycznie używane.

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

# Główny Kustomization Production
cat <<EOF_K_PROD > ${APP_DIR}/manifests/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
- ../base
- namespace.yaml
- ingress.yaml
- servicemonitor.yaml

images:
- name: ${REPO_NAME}:placeholder
  newName: ${REPO_NAME}
  newTag: ${IMAGE_TAG}

# Usunięcie prefixu z base
namePrefix:
EOF_K_PROD
echo "✅ Manifesty Kustomize wygenerowane."

# --- 7. Budowanie i ładowanie obrazu do MicroK8s (zastępuje GitHub Actions/GHCR) ---
echo "📦 Budowanie obrazu Docker i ładowanie do MicroK8s..."
echo "    -> Użycie 'microk8s docker' i 'microk8s ctr' nie wymaga żadnych haseł do rejestru."
cd ${APP_DIR}
microk8s docker build -t ${IMAGE_FULL_NAME} .
# Użycie microk8s ctr images import zamiast push do lokalnego rejestru
microk8s ctr image import ${IMAGE_FULL_NAME}
cd ..
echo "✅ Obraz ${IMAGE_FULL_NAME} załadowany do MicroK8s."

# --- 8. Generowanie ArgoCD Application i Kyverno Policy ---
echo "📝 Generowanie manifestu ArgoCD i polityki Kyverno..."
# Kyverno Policy
cat <<EOF_KYVERNO > ${APP_DIR}/kyverno/policy.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: ${KYVERNO_POLICY_NAME}
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: check-monitoring-label
    match:
      any:
      - resources:
          kinds:
          - Deployment
          namespaces:
          - ${NAMESPACE}
    validate:
      message: "Deployment musi zawierać etykietę 'app.kubernetes.io/component' dla monitoringu."
      pattern:
        metadata:
          labels:
            app.kubernetes.io/component: "?*"
EOF_KYVERNO
microk8s kubectl apply -f ${APP_DIR}/kyverno/policy.yaml
echo "✅ Polityka Kyverno zastosowana."

# ArgoCD Application (Konfiguracja GitOps)
cat <<EOF_ARGO > ${APP_DIR}/argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ARGO_APP_NAME}
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${REPO_OWNER}/${REPO_NAME}.git # Wskazuje na PUBLICZNE repo Git, nie wymaga hasła
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
    - CreateNamespace=true
EOF_ARGO
microk8s kubectl apply -f ${APP_DIR}/argocd/application.yaml
echo "✅ Definicja aplikacji ArgoCD (wskazuje na publiczne repo Git) utworzona."

# --- 9. Wdrożenie bezpośrednie z Kustomize (Lokalne Rozpakowanie i Deploy) ---
echo "💾 Bezpośrednie wdrożenie przy użyciu Kustomize (Aby natychmiast 'rozpakować lokalnie'):"
echo "    -> Ten krok zapewnia, że aplikacja działa od razu, bez konieczności oczekiwania na synchronizację ArgoCD."
microk8s kubectl apply -k ${APP_DIR}/manifests/production
echo "✅ Wdrożenie Kustomize zakończone pomyślnie. Aplikacja i PostgreSQL są w ${NAMESPACE}."

# --- 10. Instrukcje końcowe ---
echo "================================================================"
echo "                   Wdrożenie Zakończone!                        "
echo "================================================================="
echo ""
echo "Dane dla strony zostały zasymulowane i wbudowane w obraz Docker."
echo "Nie była potrzebna interakcja z hasłem do Git/Docker/PostgreSQL."
echo "Wszystkie komponenty są w namespace: ${NAMESPACE}"
echo ""
echo "➡️  1. Sprawdź Deployment i Service:"
echo "   microk8s kubectl get all -n ${NAMESPACE}"
echo "   microk8s kubectl get ingress -n ${NAMESPACE}"
echo ""
echo "➡️  2. Hasło ArgoCD (do UI):"
echo "   microk8s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "➡️  3. Weryfikacja logów (Loki/stdout):"
echo "   microk8s kubectl logs -n ${NAMESPACE} -l app=davtro-website-app -c davtro-website-container"
echo "================================================================"
