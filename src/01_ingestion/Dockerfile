FROM golang:1.26.1-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o ingestor ./cmd/ingestor/main.go

FROM alpine:3.20.9
WORKDIR /root/

COPY --from=builder /app/ingestor .

CMD ["./ingestor"]
