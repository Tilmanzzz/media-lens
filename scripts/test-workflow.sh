#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "1/5: Tearing down existing containers and volumes..."
docker compose down -v

echo "2/5: Starting infrastructure and transcription worker in the background..."
docker compose up -d postgres minio redis transcription --build

# Using 'docker compose run' automatically waits for the healthchecks
# defined in 'depends_on' before executing the container's main process.

echo "3/5: Running insertion service..."
docker compose --profile tools run --rm insertion

echo "4/5: Running ingestion service..."
docker compose run --rm ingestion

echo "5/5: Pipeline triggered. Tailing transcription logs..."
docker compose logs -f transcription
