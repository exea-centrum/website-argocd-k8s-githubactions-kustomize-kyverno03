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
	pageContent = `<h2>O Mnie</h2>
<p>Jestem entuzjastą DevOps, specjalizującym się w automatyzacji, konteneryzacji (Docker, Kubernetes) oraz CI/CD. To wdrożenie jest zarządzane przez ArgoCD, które synchronizuje manifesty z repozytorium GitHub.</p>
<h2>Technologie w Użyciu</h2>
<ul>
    <li><strong>Język Backend:</strong> GoLang (z metrykami Prometheus)</li>
    <li><strong>Orkiestracja:</strong> MicroK8s</li>
    <li><strong>Wdrożenie GitOps:</strong> ArgoCD & Kustomize (pobrane z GitHuba)</li>
    <li><strong>CI/CD:</strong> GitHub Actions (budowanie i push obrazu)</li>
    <li><strong>Baza Danych:</strong> PostgreSQL (w osobnym Deployment)</li>
</ul>`
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
	
	htmlContent := fmt.Sprintf(`
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
`, DB_NAME, pageContent, dbStatus)

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
