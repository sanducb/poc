#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RECEIVER_NODE_URL="http://localhost:7780"
ADMIN_TOKEN="receiver-admin-token"

echo "Configuring RECEIVER node..."

# Wait for node to be ready
echo "Waiting for receiver node to be ready..."
for i in {1..30}; do
    if curl -s "$RECEIVER_NODE_URL/" > /dev/null 2>&1; then
        echo "Receiver node is ready!"
        break
    fi
    sleep 1
done

# Create the Rafiki peer account
echo "Creating Rafiki peer account on receiver node..."
curl -s -X POST "$RECEIVER_NODE_URL/accounts" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$ROOT_DIR/infra/accounts/rafiki-peer-receiver.json" | jq . 2>/dev/null || echo "(created)"

# Add static route for test.sender via Rafiki
echo "Adding static route: test.sender → rafiki"
ILP_CLI="$ROOT_DIR/interledger-rs/target/release/ilp-cli"
if [ -f "$ILP_CLI" ]; then
    "$ILP_CLI" --node "$RECEIVER_NODE_URL" routes set-all \
        --auth "$ADMIN_TOKEN" \
        --pair "test.sender" rafiki \
        --pair "test.rafiki" rafiki
else
    echo "Warning: ilp-cli not built, skipping route setup"
fi

echo ""
echo "✓ Receiver node configured"

