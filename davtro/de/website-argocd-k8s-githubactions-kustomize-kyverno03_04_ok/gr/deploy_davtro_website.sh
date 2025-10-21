#!/bin/bash

# ================================
# Davtro Website Local Deployment Script for MicroK8s with ArgoCD, Kustomize, Go, PostgreSQL
# ================================

# Konfiguracja
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno03"
NAMESPACE="davtro"
IMAGE_NAME="davtro-website"
LOCAL_IMAGE="localhost:32000/${IMAGE_NAME}:latest"
KUSTOMIZE_PATH="./manifests/production"
ARGOCD_APP_NAME="davtro-website-app"
MONITORING_NS="monitoring"

# Kolory dla czytelności
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Funkcja sprawdzająca wymagania
check_prerequisites() {
    echo "🔍 Sprawdzanie wymagań..."
    for cmd in git microk8s kubectl helm docker curl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Błąd: $cmd nie jest zainstalowany!${NC}"
            exit 1
        fi
    done
    # Sprawdź, czy MicroK8s registry jest włączony
    if ! microk8s status | grep -q "registry: enabled"; then
        echo "Włączanie rejestru MicroK8s..."
        microk8s enable registry
    fi
    echo -e "${GREEN}Wymagania spełnione!${NC}"
}

# Funkcja tworząca strukturę projektu lokalnie
setup_project_structure() {
    echo "📦 Tworzenie struktury projektu lokalnie w ${REPO_NAME}..."
    if [ -d "$REPO_NAME" ]; then
        echo "Katalog już istnieje, usuwam i tworzę nowy..."
        rm -rf $REPO_NAME
    fi
    mkdir -p ${REPO_NAME}/src \
             ${REPO_NAME}/templates \
             ${REPO_NAME}/static \
             ${REPO_NAME}/manifests/base \
             ${REPO_NAME}/manifests/production \
             ${REPO_NAME}/argocd

    cd $REPO_NAME

    # Go: main.go z sekcjami portfolio
    cat << EOF > src/main.go
package main

import (
	"database/sql"
	"fmt"
	"html/template"
	"log"
	"net/http"

	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type PageData struct {
	About     string
	Education string
	Skills    string
	Projects  string
	Experience string
	Contact   string
}

func main() {
	// Połączenie z PostgreSQL
	connStr := "postgres://postgres:password@postgres-service.${NAMESPACE}.svc.cluster.local:5432/postgres?sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Stwórz tabelę jeśli nie istnieje
	_, err = db.Exec(\`
		CREATE TABLE IF NOT EXISTS portfolio (
			id SERIAL PRIMARY KEY,
			section TEXT UNIQUE,
			content TEXT
		)
	\`)
	if err != nil {
		log.Fatal(err)
	}

	// Wstaw dane
	insertData(db)

	// Handler dla strony głównej
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		data := getData(db)
		tmpl, err := template.ParseFiles("templates/index.html")
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		tmpl.Execute(w, data)
	})

	// Endpoint dla Prometheus
	http.Handle("/metrics", promhttp.Handler())

	// Serwuj statyczne pliki (CSS)
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("static"))))

	fmt.Println("Serwer startuje na :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func insertData(db *sql.DB) {
	data := map[string]string{
		"about":     "At around 2003-04 when I was 7-8 years old, I received my first computer... My plans for future are to work within Cyber Security company that would allow me to learn and grow within the company being able to give 200% from myself.",
		"education": "BSc (Honours) in Computing & Cyber Security - Result - 2.1 (2016-2018), Higher Certificate in Computing & Cyber Security - Result - Distinction (2014-2016).",
		"skills":    "Programming: Go, Python, JavaScript; Cybersecurity: Penetration Testing, Network Security; Tools: Docker, Kubernetes, Terraform.",
		"projects":  "Developed a secure web application for portfolio management; Contributed to open-source cybersecurity tools on GitHub.",
		"experience": "Cybersecurity Intern at XYZ Corp (2017), Junior Developer at ABC Ltd (2018-2019).",
		"contact":   "Email: dawid@example.com | LinkedIn: linkedin.com/in/dawidtrojanowski | GitHub: github.com/dawidtrojanowski",
	}

	for section, content := range data {
		var count int
		db.QueryRow("SELECT COUNT(*) FROM portfolio WHERE section = \$1", section).Scan(&count)
		if count == 0 {
			_, err := db.Exec("INSERT INTO portfolio (section, content) VALUES (\$1, \$2)", section, content)
			if err != nil {
				log.Printf("Błąd przy wstawianiu %s: %v", section, err)
			}
		}
	}
}

func getData(db *sql.DB) PageData {
	data := PageData{}
	sections := []string{"about", "education", "skills", "projects", "experience", "contact"}
	for _, section := range sections {
		var content string
		row := db.QueryRow("SELECT content FROM portfolio WHERE section = \$1", section)
		if err := row.Scan(&content); err == nil {
			switch section {
			case "about":
				data.About = content
			case "education":
				data.Education = content
			case "skills":
				data.Skills = content
			case "projects":
				data.Projects = content
			case "experience":
				data.Experience = content
			case "contact":
				data.Contact = content
			}
		}
	}
	return data
}
EOF

    # HTML template
    cat << EOF > templates/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Dawid Trojanowski Portfolio</title>
    <link rel="stylesheet" href="/static/styles.css">
</head>
<body>
    <header>
        <h1>Dawid Trojanowski's Portfolio</h1>
    </header>
    <main>
        <section>
            <h2>About Me</h2>
            <p>{{.About}}</p>
        </section>
        <section>
            <h2>Education</h2>
            <p>{{.Education}}</p>
        </section>
        <section>
            <h2>Skills</h2>
            <p>{{.Skills}}</p>
        </section>
        <section>
            <h2>Projects</h2>
            <p>{{.Projects}}</p>
        </section>
        <section>
            <h2>Experience</h2>
            <p>{{.Experience}}</p>
        </section>
        <section>
            <h2>Contact</h2>
            <p>{{.Contact}}</p>
        </section>
    </main>
</body>
</html>
EOF

    # CSS
    cat << EOF > static/styles.css
body {
    font-family: Arial, sans-serif;
    margin: 40px;
    line-height: 1.6;
    background-color: #f4f4f4;
}
header {
    text-align: center;
    background-color: #333;
    color: white;
    padding: 20px;
}
h1 {
    margin: 0;
    font-size: 2.5em;
}
main {
    max-width: 800px;
    margin: 0 auto;
}
section {
    margin-bottom: 30px;
    padding: 20px;
    background-color: white;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}
h2 {
    color: #333;
    border-bottom: 2px solid #333;
    padding-bottom: 10px;
}
p {
    margin: 10px 0;
}
EOF

    # Dockerfile
    cat << EOF > Dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY src/ ./src/
COPY templates/ ./templates/
COPY static/ ./static/
RUN go mod init dawtro-website
RUN go mod tidy
RUN go build -o main ./src/main.go

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
COPY --from=builder /app/templates/ ./templates/
COPY --from=builder /app/static/ ./static/
CMD ["./main"]
EOF

    # Kustomize: Base manifests
    mkdir -p manifests/base
    cat << EOF > manifests/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtro-website-deployment
  labels:
    app: davtro-website-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davtro-website-app
  template:
    metadata:
      labels:
        app: davtro-website-app
    spec:
      containers:
        - name: website
          image: placeholder-image
          ports:
            - containerPort: 8080
          env:
            - name: POSTGRES_HOST
              value: "postgres-service.${NAMESPACE}.svc.cluster.local"
EOF

    cat << EOF > manifests/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: davtro-website-service
spec:
  selector:
    app: davtro-website-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
EOF

    cat << EOF > manifests/base/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: davtro-website-ingress
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: davtro-website-service
                port:
                  number: 80
EOF

    cat << EOF > manifests/base/postgres-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          env:
            - name: POSTGRES_USER
              value: postgres
            - name: POSTGRES_PASSWORD
              value: password
            - name: POSTGRES_DB
              value: postgres
          ports:
            - containerPort: 5432
EOF

    cat << EOF > manifests/base/postgres-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
spec:
  selector:
    app: postgres
  ports:
    - protocol: TCP
      port: 5432
      targetPort: 5432
  type: ClusterIP
EOF

    cat << EOF > manifests/base/kustomization.yaml
resources:
- deployment.yaml
- service.yaml
- ingress.yaml
- postgres-deployment.yaml
- postgres-service.yaml
EOF

    # Kustomize: Production overlay
    mkdir -p manifests/production
    cat << EOF > manifests/production/kustomization.yaml
bases:
- ../base
namespace: ${NAMESPACE}
images:
- name: placeholder-image
  newName: ${LOCAL_IMAGE}
  newTag: latest
patchesStrategicMerge:
- deployment-patch.yaml
EOF

    cat << EOF > manifests/production/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: davtro-website-deployment
spec:
  template:
    spec:
      containers:
        - name: website
          resources:
            limits:
              cpu: 500m
              memory: 512Mi
EOF

    # Kyverno Policy
    cat << EOF > manifests/production/kyverno-policy.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-image-signature
spec:
  validationFailureAction: enforce
  rules:
  - name: check-signature
    match:
      resources:
        kinds:
        - Pod
    verifyImages:
    - image: "localhost:32000/*"
      key: "public-key" # Dodaj klucz Cosign jeśli używasz
EOF

    # ArgoCD Application
    cat << EOF > argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ARGOCD_APP_NAME}
  namespace: argocd
spec:
  project: default
  source:
    path: ${KUSTOMIZE_PATH}
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

    # Monitoring Application
    cat << EOF > argocd/monitoring-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 65.1.0
    chart: kube-prometheus-stack
    helm:
      values: |
        grafana:
          enabled: true
          adminPassword: "prom-operator"
        prometheus:
          enabled: true
        loki:
          enabled: true
        tempo:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: ${MONITORING_NS}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

    cd ..
}

# Funkcja budująca i publikująca obraz lokalnie
build_and_push_image() {
    echo "🛠️ Budowanie i publikowanie obrazu do lokalnego rejestru MicroK8s..."
    cd $REPO_NAME
    docker build -t ${LOCAL_IMAGE} .
    if [ $? -ne 0 ]; then
        echo -e "${RED}Błąd podczas budowania obrazu!${NC}"
        exit 1
    fi
    docker push ${LOCAL_IMAGE}
    if [ $? -ne 0 ]; then
        echo -e "${RED}Błąd podczas publikowania obrazu do lokalnego rejestru!${NC}"
        exit 1
    fi
    cd ..
    echo -e "${GREEN}Obraz ${LOCAL_IMAGE} zbudowany i opublikowany!${NC}"
}

# Funkcja konfigurująca namespace w MicroK8s
setup_namespace() {
    echo "🏗️ Tworzenie namespace ${NAMESPACE} i ${MONITORING_NS}..."
    microk8s kubectl create namespace $NAMESPACE --dry-run=client -o yaml | microk8s kubectl apply -f -
    microk8s kubectl create namespace $MONITORING_NS --dry-run=client -o yaml | microk8s kubectl apply -f -
    if [ $? -ne 0 ]; then
        echo -e "${RED}Błąd podczas tworzenia namespace!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Namespaces gotowe!${NC}"
}

# Funkcja konfigurująca Kyverno
setup_kyverno() {
    echo "🔒 Instalacja Kyverno..."
    microk8s helm repo add kyverno https://kyverno.github.io/kyverno/
    microk8s helm repo update
    microk8s helm install kyverno kyverno/kyverno -n kyverno --create-namespace
    if [ $? -ne 0 ]; then
        echo -e "${RED}Błąd podczas instalacji Kyverno!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Kyverno zainstalowane!${NC}"
}

# Funkcja konfigurująca ArgoCD Application
setup_argocd_application() {
    echo "🚀 Konfiguracja aplikacji ArgoCD ${ARGOCD_APP_NAME}..."
    # Kopiuj manifesty do tymczasowego katalogu, aby ArgoCD mógł je odczytać lokalnie
    mkdir -p /tmp/argocd-manifests
    cp -r ${REPO_NAME}/manifests /tmp/argocd-manifests/
    cp ${REPO_NAME}/argocd/application.yaml /tmp/argocd-manifests/
    cp ${REPO_NAME}/argocd/monitoring-app.yaml /tmp/argocd-manifests/
    microk8s kubectl apply -f /tmp/argocd-manifests/application.yaml
    microk8s kubectl apply -f /tmp/argocd-manifests/monitoring-app.yaml
    if [ $? -ne 0 ]; then
        echo -e "${RED}Błąd podczas konfiguracji aplikacji ArgoCD!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Aplikacje ArgoCD skonfigurowane!${NC}"
}

# Funkcja sprawdzająca status wdrożenia
check_deployment_status() {
    echo "🔎 Sprawdzanie statusu wdrożenia..."
    sleep 10
    microk8s kubectl -n $NAMESPACE get pods
    microk8s kubectl -n $NAMESPACE get svc
    microk8s kubectl -n $NAMESPACE get ingress
    microk8s kubectl -n $MONITORING_NS get pods
    echo "Sprawdź ArgoCD UI: 'microk8s kubectl port-forward svc/argocd-server -n argocd 8080:80' i odwiedź http://localhost:8080"
    echo "Sprawdź Grafana: 'microk8s kubectl port-forward svc/grafana -n $MONITORING_NS 3000:80' (login: admin, hasło: prom-operator)"
    echo "Sprawdź stronę: 'microk8s kubectl port-forward svc/davtro-website-service -n $NAMESPACE 8080:80' i odwiedź http://localhost:8080"
}

# Główna funkcja
main() {
    check_prerequisites
    setup_project_structure
    build_and_push_image
    setup_namespace
    setup_kyverno
    setup_argocd_application
    check_deployment_status
    echo -e "${GREEN}Wdrożenie lokalne zakończone! Strona z portfolio dostępna w namespace ${NAMESPACE}, monitoring w ${MONITORING_NS}.${NC}"
}

# Uruchom
main