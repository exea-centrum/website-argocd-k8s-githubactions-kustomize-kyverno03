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
