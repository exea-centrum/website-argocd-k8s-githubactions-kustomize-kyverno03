FROM golang:1.21-alpine AS builder
WORKDIR /src
COPY go.mod .
COPY src/ ./
RUN CGO_ENABLED=0 go build -o /app ./src

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app /app
USER nonroot
ENTRYPOINT ["/app"]
