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
