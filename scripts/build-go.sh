#!/bin/bash
# Build Go backend binary

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"

if ! command -v go &> /dev/null; then
    echo "Error: Go not found. Please install Go 1.24+."
    exit 1
fi

if [ ! -f "$BACKEND_DIR/go.mod" ]; then
    echo "Error: backend/go.mod not found at $BACKEND_DIR"
    exit 1
fi

mkdir -p "$PROJECT_DIR/bin"

echo "=== Building Go backend ==="
echo "Source: $BACKEND_DIR"
echo ""

cd "$BACKEND_DIR"
go build -o "$PROJECT_DIR/bin/mocode" ./cmd/mocode

BINARY="$PROJECT_DIR/bin/mocode"
echo "✓ Binary built: $BINARY"
echo "  Size: $(du -h "$BINARY" | cut -f1)"

# Cross-compile for Android ARM64 if requested.
if [ "$1" = "--android" ]; then
    echo ""
    echo "Cross-compiling for Android ARM64..."
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "$PROJECT_DIR/bin/mocode-arm64" ./cmd/mocode
    echo "✓ ARM64 binary: $PROJECT_DIR/bin/mocode-arm64"
    echo "  Size: $(du -h "$PROJECT_DIR/bin/mocode-arm64" | cut -f1)"
fi
