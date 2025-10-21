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
	connStr := "postgres://postgres:password@postgres-service.davtro.svc.cluster.local:5432/postgres?sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Stwórz tabelę jeśli nie istnieje
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS portfolio (
			id SERIAL PRIMARY KEY,
			section TEXT UNIQUE,
			content TEXT
		)
	`)
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
		db.QueryRow("SELECT COUNT(*) FROM portfolio WHERE section = $1", section).Scan(&count)
		if count == 0 {
			_, err := db.Exec("INSERT INTO portfolio (section, content) VALUES ($1, $2)", section, content)
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
		row := db.QueryRow("SELECT content FROM portfolio WHERE section = $1", section)
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
