#!/bin/bash
# Project setup — install dependencies and verify toolchain

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== Mo-Code Project Setup ==="
echo "Project root: $PROJECT_DIR"
echo ""

# Check Go
if command -v go &> /dev/null; then
    echo "✓ Go: $(go version)"
else
    echo "✗ Go not found. Install: https://go.dev/dl/"
fi

# Check Flutter
if command -v flutter &> /dev/null; then
    echo "✓ Flutter: $(flutter --version | head -1)"
else
    echo "✗ Flutter not found. Install: https://docs.flutter.dev/get-started/install"
fi

echo ""

# Install Go dependencies
echo "=== Installing Go dependencies ==="
if command -v go &> /dev/null && [ -f backend/go.mod ]; then
    (cd backend && go mod download)
    echo "✓ Go modules downloaded"
else
    echo "Skipping Go (not installed or no go.mod)"
fi

echo ""

# Install Flutter dependencies
echo "=== Installing Flutter dependencies ==="
if command -v flutter &> /dev/null && [ -d flutter ]; then
    (cd flutter && flutter pub get)
    echo "✓ Flutter packages installed"
else
    echo "Skipping Flutter (not installed or flutter/ not found)"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To start daemon:   ./scripts/start-server.sh"
echo "To build Flutter:  ./scripts/build-flutter.sh"
echo "To build Go:       ./scripts/build-go.sh"
echo "To run tests:      ./scripts/test.sh"
echo "To build release:  ./scripts/release.sh"
