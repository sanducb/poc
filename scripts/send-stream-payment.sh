#!/bin/bash
set -e

# STREAM Payment Sender Script
# Sends a payment from Sender Node → Rafiki → Receiver Node → Ethereum Payout
#
# The ILP destination format is:
#   test.receiver.eth.{chainId}.{asset}.{recipient}.{streamToken}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
AMOUNT=${1:-1000000}  # 1 EURC (6 decimals)
RECIPIENT=${2:-"0x70997970C51812dc3A010C7d01b50e0d17dc79C8"}
CHAIN_ID=${3:-31337}
ASSET_CODE=${4:-EURC}

# Node URLs
SENDER_NODE_URL="http://localhost:7770"
RECEIVER_NODE_URL="http://localhost:7780"
SENDER_ADMIN_TOKEN="sender-admin-token"
RECEIVER_ADMIN_TOKEN="receiver-admin-token"

ILP_CLI="$ROOT_DIR/interledger-rs/target/release/ilp-cli"

echo "=========================================="
echo "  Sending STREAM Payment via Rafiki      "
echo "=========================================="
echo ""
echo "Route: Sender (7770) → Rafiki → Receiver (7780) → Ethereum"
echo ""
echo "Amount:    $AMOUNT (scale 6)"
echo "Recipient: $RECIPIENT"
echo "Chain ID:  $CHAIN_ID"
echo "Asset:     $ASSET_CODE"
echo ""

# Build ilp-cli if not exists
if [ ! -f "$ILP_CLI" ]; then
    echo "Building ilp-cli..."
    cd "$ROOT_DIR/interledger-rs"
    cargo build --release -p ilp-cli
    cd "$ROOT_DIR"
fi

# Create sender account on the sender node
SENDER_TOKEN="sender-auth-token"

echo "Setting up sender account on sender node..."
curl -s -X DELETE "$SENDER_NODE_URL/accounts/sender" \
    -H "Authorization: Bearer $SENDER_ADMIN_TOKEN" 2>/dev/null || true

curl -s -X POST "$SENDER_NODE_URL/accounts" \
    -H "Authorization: Bearer $SENDER_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"sender\",
        \"ilp_address\": \"test.sender.user\",
        \"asset_code\": \"$ASSET_CODE\",
        \"asset_scale\": 6,
        \"max_packet_amount\": 1000000000,
        \"ilp_over_http_incoming_token\": \"$SENDER_TOKEN\"
    }" | jq . 2>/dev/null || echo "(created)"

echo "Sender account ready"
echo ""

# Create receiver account on the receiver node
# The receiver's ILP address encodes the Ethereum payout details
RECEIVER_ILP_ADDRESS="test.receiver.eth.$CHAIN_ID.$ASSET_CODE.$RECIPIENT"

echo "Setting up receiver account on receiver node..."
curl -s -X DELETE "$RECEIVER_NODE_URL/accounts/ethreceiver" \
    -H "Authorization: Bearer $RECEIVER_ADMIN_TOKEN" 2>/dev/null || true

curl -s -X POST "$RECEIVER_NODE_URL/accounts" \
    -H "Authorization: Bearer $RECEIVER_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"ethreceiver\",
        \"ilp_address\": \"$RECEIVER_ILP_ADDRESS\",
        \"asset_code\": \"$ASSET_CODE\",
        \"asset_scale\": 6,
        \"max_packet_amount\": 1000000000
    }" | jq . 2>/dev/null || echo "(created)"

echo "Receiver account ready: $RECEIVER_ILP_ADDRESS"
echo ""

# Get SPSP credentials from the receiver node (use proper Accept header)
echo "Fetching SPSP credentials from receiver node..."
SPSP_RESPONSE=$(curl -s -H "Accept: application/spsp4+json" "$RECEIVER_NODE_URL/accounts/ethreceiver/spsp")
echo "SPSP: $SPSP_RESPONSE"

# Extract destination and shared secret
DESTINATION=$(echo "$SPSP_RESPONSE" | jq -r '.destination_account // empty')
SHARED_SECRET=$(echo "$SPSP_RESPONSE" | jq -r '.shared_secret // empty')

if [ -z "$DESTINATION" ] || [ -z "$SHARED_SECRET" ]; then
    echo "Warning: Could not get SPSP credentials. Trying payment pointer format..."
fi
echo ""

# Send payment from sender node using SPSP URL
echo "Sending payment..."
"$ILP_CLI" --node "$SENDER_NODE_URL" pay sender \
    --auth "$SENDER_TOKEN" \
    --amount "$AMOUNT" \
    --to "http://localhost:7780/accounts/ethreceiver/spsp"

echo ""
echo "✓ Payment sent!"
echo ""