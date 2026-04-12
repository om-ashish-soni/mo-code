#!/bin/bash
# Project setup - install dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Mo-Code Project Setup ==="

# Check OpenCode
if command -v opencode &> /dev/null; then
    echo "✓ OpenCode: $(opencode --version)"
else
    echo "✗ OpenCode not found. Install: curl -fsSL https://opencode.ai/install | bash"
fi

# Check Go
if command -v go &> /dev/null; then
    echo "✓ Go: $(go version)"
else
    echo "✗ Go not found."
fi

# Check Flutter
if command -v flutter &> /dev/null; then
    echo "✓ Flutter: $(flutter --version | head -1)"
else
    echo "✗ Flutter not found (optional for backend only)"
fi

echo ""
echo "=== Installing Flutter dependencies ==="
if command -v flutter &> /dev/null; then
    cd flutter
    flutter pub get
    cd ..
else
    echo "Skipping Flutter (not installed)"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To start OpenCode server: ./scripts/start-server.sh"
echo "To build Flutter: ./scripts/build-flutter.sh"
echo "To build Go: ./scripts/build-go.sh"
echo "To run tests: ./scripts/test.sh"
