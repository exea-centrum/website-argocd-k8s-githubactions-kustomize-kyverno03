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
