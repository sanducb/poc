#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  POC Infrastructure Setup                 ${NC}"
echo -e "${BLUE}  (Anvil + Smart Contracts)                ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v forge &> /dev/null; then
    echo -e "${RED}Error: Foundry is not installed. Install with:${NC}"
    echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Step 2: Start Anvil
echo -e "${YELLOW}Starting Anvil (local Ethereum node)...${NC}"

# Check if Anvil is already running
if curl -s http://localhost:8545 > /dev/null 2>&1; then
    echo "Anvil is already running on port 8545"
else
    # Start Anvil in background
    anvil --host 0.0.0.0 --chain-id 31337 > /tmp/anvil.log 2>&1 &
    ANVIL_PID=$!
    echo "Started Anvil with PID $ANVIL_PID"
    echo "$ANVIL_PID" > "$ROOT_DIR/.anvil.pid"
    
    # Wait for Anvil to be ready
    echo "Waiting for Anvil to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8545 > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    if ! curl -s http://localhost:8545 > /dev/null 2>&1; then
        echo -e "${RED}Error: Anvil failed to start${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Anvil running at http://localhost:8545${NC}"
echo ""

# Step 3: Deploy smart contracts
echo -e "${YELLOW}Deploying smart contracts...${NC}"
cd "$ROOT_DIR/contracts"

# Install Foundry dependencies if not present
if [ ! -d "lib/forge-std" ]; then
    echo "Installing Foundry dependencies..."
    forge install foundry-rs/forge-std --no-git
    forge install OpenZeppelin/openzeppelin-contracts --no-git
fi

# Deploy contracts
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast

# Read addresses
if [ -f "addresses.json" ]; then
    TREASURY_ADDRESS=$(grep -o '"treasury":"[^"]*"' addresses.json | cut -d'"' -f4)
    EURC_ADDRESS=$(grep -o '"eurc":"[^"]*"' addresses.json | cut -d'"' -f4)
    
    echo ""
    echo -e "${GREEN}✓ Contracts deployed:${NC}"
    echo "  EURC:     $EURC_ADDRESS"
    echo "  Treasury: $TREASURY_ADDRESS"
    
    # Update eth-connector.env with Treasury address
    if [ -f "$ROOT_DIR/infra/eth-connector.env" ]; then
        sed -i.bak "s|TREASURY_ADDRESS=.*|TREASURY_ADDRESS=$TREASURY_ADDRESS|" "$ROOT_DIR/infra/eth-connector.env"
        rm -f "$ROOT_DIR/infra/eth-connector.env.bak"
        echo ""
        echo -e "${GREEN}✓ Updated eth-connector.env with Treasury address${NC}"
    fi
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  POC Infrastructure Ready!                ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next step: Start the ILP node with Ethereum payout support:"
echo ""
echo "  ./scripts/start-ilp-node.sh"
echo ""
echo "Then send a test payment:"
echo ""
echo "  ./scripts/send-stream-payment.sh 1000000 0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
echo ""
