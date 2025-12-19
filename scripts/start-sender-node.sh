#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  Starting SENDER Node (test.sender)     "
echo "=========================================="
echo ""

# Check if Redis is running on port 6379
if ! redis-cli -p 6379 ping > /dev/null 2>&1; then
    echo "Starting Redis for sender node (port 6379)..."
    # Remove any existing container with the same name
    docker rm -f ilp-redis-sender 2>/dev/null || true
    docker run -d --name ilp-redis-sender -p 6379:6379 redis:7-alpine
    sleep 2
fi

echo "Redis (sender) running on port 6379"

cd "$ROOT_DIR/interledger-rs"

# Build the node (without ethereum-payout - sender doesn't need it)
if [ ! -f "target/release/ilp-node" ]; then
    echo "Building interledger-rs..."
    cargo build --release -p ilp-node -p ilp-cli
fi

echo ""
echo "Configuration:"
echo "  ILP Address: test.sender"
echo "  HTTP Port:   7770"
echo "  Redis:       localhost:6379"
echo ""

# Start the sender node
RUST_LOG=info ./target/release/ilp-node "$ROOT_DIR/infra/sender-node-config.json"

