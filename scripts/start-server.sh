#!/bin/bash
# Start mo-code daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Building mo-code daemon..."
cd backend
go build -o mocode ./cmd/mocode

# Kill any existing daemon
pkill -f "./mocode" 2>/dev/null || true
sleep 1

echo "Starting mo-code daemon..."
nohup ./mocode > "$PROJECT_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!

# Wait for server to be ready
echo "Waiting for daemon..."
for i in {1..15}; do
    PORT=$(cat "$PROJECT_DIR/daemon_port" 2>/dev/null || echo "")
    if [ -n "$PORT" ] && curl -s "http://127.0.0.1:$PORT/api/health" > /dev/null 2>&1; then
        echo "mo-code daemon ready on port $PORT"
        break
    fi
    sleep 1
done

echo "Daemon PID: $DAEMON_PID"
echo "Port file: $PROJECT_DIR/daemon_port"
echo "Log: $PROJECT_DIR/daemon.log"
echo ""
echo "To stop: kill $DAEMON_PID"
