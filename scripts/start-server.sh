#!/bin/bash
# Start OpenCode server and Flutter app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting OpenCode server..."

# Kill any existing server on port 4096
lsof -ti:4096 | xargs -r kill -9 2>/dev/null || true

# Start OpenCode in background
nohup opencode serve --port 4096 > /tmp/opencode.log 2>&1 &
OPENCODE_PID=$!

# Wait for server to be ready
echo "Waiting for OpenCode server..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:4096/global/health > /dev/null 2>&1; then
        echo "OpenCode server ready on port 4096"
        break
    fi
    sleep 1
done

echo "OpenCode server PID: $OPENCODE_PID"
echo "Log: /tmp/opencode.log"
echo ""
echo "To stop: kill $OPENCODE_PID"
