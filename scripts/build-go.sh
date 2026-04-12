#!/bin/bash
# Build Go backend

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR/backend"

echo "Building Go backend..."

go build -o ../bin/mocode ./cmd/mocode

echo "Done! Binary: bin/mocode"
