GOPATH=$(shell go env GOPATH)
SWAG=$(GOPATH)/bin/swag

.PHONY: swag build run

swag:
	$(SWAG) init -g cmd/server/main.go

build: swag
	go build -o bin/server cmd/server/main.go

run: swag
	go run cmd/server/main.go
