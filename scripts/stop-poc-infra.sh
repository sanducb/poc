#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Stopping POC Infrastructure..."

# Stop Anvil
if [ -f "$ROOT_DIR/.anvil.pid" ]; then
    ANVIL_PID=$(cat "$ROOT_DIR/.anvil.pid")
    if kill -0 "$ANVIL_PID" 2>/dev/null; then
        echo "Stopping Anvil (PID: $ANVIL_PID)..."
        kill "$ANVIL_PID" || true
    fi
    rm -f "$ROOT_DIR/.anvil.pid"
fi

# Also try to kill any other Anvil processes
pkill -f "anvil" 2>/dev/null || true

# Stop Redis if running
if docker ps -q -f name=ilp-redis 2>/dev/null | grep -q .; then
    echo "Stopping Redis container..."
    docker stop ilp-redis 2>/dev/null || true
fi

echo "✓ POC Infrastructure stopped."
