#!/bin/bash
# Start mo-code daemon (build + run)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"

if ! command -v go &> /dev/null; then
    echo "Error: Go not found."
    exit 1
fi

if [ ! -f "$BACKEND_DIR/go.mod" ]; then
    echo "Error: backend/go.mod not found"
    exit 1
fi

echo "Building mo-code daemon..."
cd "$BACKEND_DIR"
go build -o mocode ./cmd/mocode

# Kill any existing daemon
pkill -f "$BACKEND_DIR/mocode" 2>/dev/null || true
sleep 1

echo "Starting mo-code daemon..."
nohup "$BACKEND_DIR/mocode" > "$PROJECT_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!

# Wait for server to be ready
echo "Waiting for daemon (pid $DAEMON_PID)..."
PORT_FILE="$PROJECT_DIR/backend/daemon_port"
for i in {1..15}; do
    if [ ! -d "/proc/$DAEMON_PID" ]; then
        echo "Error: daemon exited. Check $PROJECT_DIR/daemon.log"
        exit 1
    fi
    PORT=$(cat "$PORT_FILE" 2>/dev/null || echo "")
    if [ -n "$PORT" ] && curl -s "http://127.0.0.1:$PORT/api/health" > /dev/null 2>&1; then
        echo ""
        echo "✓ mo-code daemon ready"
        echo "  PID:  $DAEMON_PID"
        echo "  Port: $PORT"
        echo "  Log:  $PROJECT_DIR/daemon.log"
        echo ""
        echo "To stop: kill $DAEMON_PID"
        exit 0
    fi
    sleep 1
done

echo "Warning: daemon started but health check not responding after 15s"
echo "PID: $DAEMON_PID | Log: $PROJECT_DIR/daemon.log"
