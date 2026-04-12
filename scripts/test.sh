#!/bin/bash
# Run all tests: Go unit tests + Dart analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FAILED=0

echo "=== Running Go tests ==="
if [ -f "$PROJECT_DIR/backend/go.mod" ]; then
    (cd "$PROJECT_DIR/backend" && go test ./...) || FAILED=1
else
    echo "Skipping: backend/go.mod not found"
fi

echo ""
echo "=== Running Dart analysis ==="
if [ -d "$PROJECT_DIR/flutter/lib" ]; then
    (cd "$PROJECT_DIR/flutter" && dart analyze lib/) || FAILED=1
else
    echo "Skipping: flutter/lib not found"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "=== All checks passed ==="
else
    echo "=== Some checks FAILED ==="
    exit 1
fi
