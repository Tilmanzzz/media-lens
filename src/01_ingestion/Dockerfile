# Builder
FROM golang:1.26.1-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o ingestion 01_ingestion/cmd/ingestion/main.go

RUN CGO_ENABLED=0 GOOS=linux go build -o insertion 01_ingestion/cmd/insertion/main.go

# Ingestion
FROM alpine:3.20.9 AS ingestion
WORKDIR /root/
COPY --from=builder /app/ingestion .
# The ingestor just runs in a loop, no args needed
CMD ["./ingestion"]

# Insertion
FROM alpine:3.20.9 AS insertion
WORKDIR /root/
COPY --from=builder /app/insertion .
# ENTRYPOINT allows us to pass the <rss_url> as an argument easily
ENTRYPOINT ["./insertion"]
