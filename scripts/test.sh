#!/bin/bash
# Run all tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== Running Go tests ==="
cd backend
go test ./...

echo ""
echo "=== Running Dart analysis ==="
cd "$PROJECT_DIR/flutter"
dart analyze

echo ""
echo "=== All checks passed ==="
