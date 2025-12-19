#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  Starting RECEIVER Node (test.receiver) "
echo "  (with Ethereum Payout support)         "
echo "=========================================="
echo ""

# Check if Redis is running on port 6380
if ! redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "Starting Redis for receiver node (port 6380)..."
    # Remove any existing container with the same name
    docker rm -f ilp-redis-receiver 2>/dev/null || true
    docker run -d --name ilp-redis-receiver -p 6380:6379 redis:7-alpine
    sleep 2
fi

echo "Redis (receiver) running on port 6380"

# Load Ethereum configuration
if [ -f "$ROOT_DIR/infra/eth-connector.env" ]; then
    echo "Loading Ethereum configuration..."
    source "$ROOT_DIR/infra/eth-connector.env"
    export ETHEREUM_RPC_URL
    export TREASURY_ADDRESS
    export OPERATOR_PRIVATE_KEY
    export CHAIN_ID
    echo "  Treasury:     $TREASURY_ADDRESS"
    echo "  Chain ID:     $CHAIN_ID"
    echo "  RPC URL:      $ETHEREUM_RPC_URL"
else
    echo "WARNING: eth-connector.env not found - Ethereum payouts will be disabled"
fi

cd "$ROOT_DIR/interledger-rs"

# Build the node WITH ethereum-payout feature
echo ""
echo "Building interledger-rs with ethereum-payout feature..."
cargo build --release -p ilp-node -p ilp-cli --features ilp-node/ethereum-payout

echo ""
echo "Configuration:"
echo "  ILP Address: test.receiver"
echo "  HTTP Port:   7780"
echo "  Redis:       localhost:6380"
echo "  Ethereum:    ENABLED"
echo ""

# Start the receiver node with environment variables
RUST_LOG=info \
ETHEREUM_RPC_URL="$ETHEREUM_RPC_URL" \
TREASURY_ADDRESS="$TREASURY_ADDRESS" \
OPERATOR_PRIVATE_KEY="$OPERATOR_PRIVATE_KEY" \
CHAIN_ID="$CHAIN_ID" \
./target/release/ilp-node "$ROOT_DIR/infra/receiver-node-config.json"

