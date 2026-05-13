FROM golang:1.26.1-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o worker ./02_processing/transcription/main.go

FROM alpine:3.20.9
RUN apk add --no-cache ffmpeg ca-certificates
WORKDIR /root/
COPY --from=builder /app/worker .
CMD ["./worker"]
