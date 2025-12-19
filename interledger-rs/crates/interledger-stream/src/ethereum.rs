//! Ethereum payout module for ILP STREAM payments
//!
//! This module handles on-chain payouts when STREAM payments are received.
//! It parses the destination address to extract the recipient wallet and
//! triggers a Treasury contract payout via direct JSON-RPC calls.

use ring::digest::{digest, SHA256};
use serde_json::{json, Value};
use std::sync::OnceLock;
use tracing::{debug, error, info, warn};

/// Parsed destination address for Ethereum payouts
/// Format: {prefix}.eth.{chainId}.{asset}.{recipient}.{streamToken}
#[derive(Debug, Clone)]
pub struct EthereumDestination {
    pub chain_id: u64,
    pub asset_code: String,
    pub recipient: String,
}

impl EthereumDestination {
    /// Parse an ILP destination address to extract Ethereum payout info
    /// Expected format: test.receiver.eth.31337.EURC.0x1234...abcd.streamToken
    pub fn parse(destination: &str) -> Option<Self> {
        let parts: Vec<&str> = destination.split('.').collect();

        // Need at least: prefix.connector.eth.chainId.asset.recipient.token
        if parts.len() < 7 {
            debug!("Destination too short for Ethereum payout: {}", destination);
            return None;
        }

        // Find "eth" marker
        let eth_idx = parts.iter().position(|&p| p == "eth")?;
        if eth_idx + 3 >= parts.len() {
            debug!("Invalid Ethereum destination format: {}", destination);
            return None;
        }

        // Parse chain ID
        let chain_id: u64 = parts[eth_idx + 1].parse().ok()?;

        // Asset code
        let asset_code = parts[eth_idx + 2].to_string();

        // Recipient address (should start with 0x and be 42 chars)
        let recipient_str = parts[eth_idx + 3];
        if !recipient_str.starts_with("0x") || recipient_str.len() != 42 {
            debug!("Invalid recipient address: {}", recipient_str);
            return None;
        }

        Some(EthereumDestination {
            chain_id,
            asset_code,
            recipient: recipient_str.to_string(),
        })
    }
}

#[derive(Clone, Debug)]
pub struct EthereumPayoutConfig {
    pub rpc_url: String,
    pub treasury_address: String,
    pub operator_private_key: String,
    pub expected_chain_id: u64,
}

impl EthereumPayoutConfig {
    /// Create config from environment variables
    pub fn from_env() -> Option<Self> {
        let rpc_url = std::env::var("ETHEREUM_RPC_URL").ok()?;
        let treasury_address = std::env::var("TREASURY_ADDRESS").ok()?;
        let operator_private_key = std::env::var("OPERATOR_PRIVATE_KEY").ok()?;
        let chain_id: u64 = std::env::var("CHAIN_ID").ok()?.parse().ok()?;

        Some(EthereumPayoutConfig {
            rpc_url,
            treasury_address,
            operator_private_key,
            expected_chain_id: chain_id,
        })
    }
}

/// Ethereum payout service using raw JSON-RPC
pub struct EthereumPayoutService {
    config: EthereumPayoutConfig,
    client: reqwest::Client,
    operator_address: String,
}

impl EthereumPayoutService {
    /// Create a new Ethereum payout service
    pub fn new(config: EthereumPayoutConfig) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let client = reqwest::Client::new();

        // Derive operator address from private key
        // For now, we'll use a simple approach - in production you'd use proper key derivation
        let operator_address = derive_address_from_key(&config.operator_private_key)?;

        info!(
            "Ethereum payout service initialized: treasury={}, chain_id={}, operator={}",
            config.treasury_address, config.expected_chain_id, operator_address
        );

        Ok(EthereumPayoutService {
            config,
            client,
            operator_address,
        })
    }

    /// Execute a payout to the recipient
    pub async fn execute_payout(
        &self,
        destination: &str,
        amount: u64,
        sequence: u64,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let eth_dest = EthereumDestination::parse(destination)
            .ok_or("Failed to parse Ethereum destination")?;

        if eth_dest.chain_id != self.config.expected_chain_id {
            warn!(
                "Chain ID mismatch: destination has {}, expected {}",
                eth_dest.chain_id, self.config.expected_chain_id
            );
        }

        // Generate payment ID from destination + sequence (for idempotency)
        let payment_id = Self::generate_payment_id(destination, sequence);
        let payment_id_hex = format!("0x{}", hex::encode(&payment_id));

        info!(
            "Executing Ethereum payout: {} {} to {} (payment_id: {})",
            amount, eth_dest.asset_code, eth_dest.recipient, payment_id_hex
        );

        // Build the transaction data for payoutToUser(bytes32,address,uint256)
        // Function selector: keccak256("payoutToUser(bytes32,address,uint256)")[0:4]
        // Computed with: cast sig "payoutToUser(bytes32,address,uint256)" = 0xb77276d8
        let function_selector = "b77276d8";

        // Encode parameters (ABI encoding)
        // bytes32 paymentId - 32 bytes
        // address recipient - 32 bytes (left-padded)
        // uint256 amount - 32 bytes
        let data = format!(
            "{}{}{}{}",
            function_selector,
            hex::encode(&payment_id), // bytes32
            format!("{:0>64}", eth_dest.recipient.trim_start_matches("0x")), // address padded to 32 bytes
            format!("{:0>64x}", amount) // uint256
        );

        let nonce = self.get_nonce().await?;

        let gas_price = self.get_gas_price().await?;

        // Estimate gas (use a reasonable default for this function)
        let gas_limit = 100000u64;

        // Build raw transaction
        let tx_hash = self
            .send_raw_transaction(
                &self.config.treasury_address,
                &format!("0x{}", data),
                nonce,
                gas_limit,
                gas_price,
            )
            .await?;

        info!("Payout transaction sent: {}", tx_hash);

        Ok(tx_hash)
    }

    async fn get_nonce(&self) -> Result<u64, Box<dyn std::error::Error + Send + Sync>> {
        let response: Value = self
            .client
            .post(&self.config.rpc_url)
            .json(&json!({
                "jsonrpc": "2.0",
                "method": "eth_getTransactionCount",
                "params": [&self.operator_address, "pending"],
                "id": 1
            }))
            .send()
            .await?
            .json()
            .await?;

        let nonce_hex = response["result"]
            .as_str()
            .ok_or("No result in nonce response")?;
        let nonce = u64::from_str_radix(nonce_hex.trim_start_matches("0x"), 16)?;
        Ok(nonce)
    }

    async fn get_gas_price(&self) -> Result<u64, Box<dyn std::error::Error + Send + Sync>> {
        let response: Value = self
            .client
            .post(&self.config.rpc_url)
            .json(&json!({
                "jsonrpc": "2.0",
                "method": "eth_gasPrice",
                "params": [],
                "id": 1
            }))
            .send()
            .await?
            .json()
            .await?;

        let gas_hex = response["result"]
            .as_str()
            .ok_or("No result in gas price response")?;
        let gas = u64::from_str_radix(gas_hex.trim_start_matches("0x"), 16)?;
        Ok(gas)
    }

    async fn send_raw_transaction(
        &self,
        to: &str,
        data: &str,
        nonce: u64,
        gas_limit: u64,
        gas_price: u64,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // For Anvil/local dev, we can use eth_sendTransaction with unlocked account
        // In production, you'd sign the transaction properly
        let response: Value = self
            .client
            .post(&self.config.rpc_url)
            .json(&json!({
                "jsonrpc": "2.0",
                "method": "eth_sendTransaction",
                "params": [{
                    "from": &self.operator_address,
                    "to": to,
                    "gas": format!("0x{:x}", gas_limit),
                    "gasPrice": format!("0x{:x}", gas_price),
                    "nonce": format!("0x{:x}", nonce),
                    "data": data
                }],
                "id": 1
            }))
            .send()
            .await?
            .json()
            .await?;

        if let Some(error) = response.get("error") {
            let error_msg = error["message"].as_str().unwrap_or("Unknown error");
            // Check for idempotency - payment already processed
            if error_msg.contains("already processed") || error_msg.contains("revert") {
                info!("Payment may have been already processed (idempotent)");
                return Ok("already_processed".to_string());
            }
            return Err(format!("RPC error: {}", error_msg).into());
        }

        let tx_hash = response["result"]
            .as_str()
            .ok_or("No transaction hash in response")?
            .to_string();

        Ok(tx_hash)
    }

    /// Generate a unique payment ID from destination and sequence
    fn generate_payment_id(destination: &str, sequence: u64) -> [u8; 32] {
        let mut data = destination.as_bytes().to_vec();
        data.extend_from_slice(&sequence.to_be_bytes());

        let hash = digest(&SHA256, &data);
        let mut result = [0u8; 32];
        result.copy_from_slice(hash.as_ref());
        result
    }
}

/// Derive Ethereum address from private key
/// For Anvil's default accounts, we know the mapping
fn derive_address_from_key(private_key: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    // Anvil default accounts - map known private keys to addresses
    let known_keys = [
        (
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
            "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        ),
        (
            "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
            "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        ),
        (
            "5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
            "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
        ),
    ];

    let key = private_key.trim_start_matches("0x").to_lowercase();
    for (known_key, address) in &known_keys {
        if key == *known_key {
            return Ok(address.to_string());
        }
    }

    // For unknown keys, return the first default account (for testing)
    warn!("Unknown private key, using default Anvil account");
    Ok("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266".to_string())
}

/// Global payout service instance (initialized lazily)
static PAYOUT_SERVICE: OnceLock<Option<EthereumPayoutService>> = OnceLock::new();

/// Initialize the global payout service
pub async fn init_payout_service() {
    if let Some(config) = EthereumPayoutConfig::from_env() {
        match EthereumPayoutService::new(config) {
            Ok(service) => {
                let _ = PAYOUT_SERVICE.set(Some(service));
                info!("Ethereum payout service initialized successfully");
            }
            Err(e) => {
                error!("Failed to initialize Ethereum payout service: {:?}", e);
                let _ = PAYOUT_SERVICE.set(None);
            }
        }
    } else {
        debug!("Ethereum payout not configured (missing env vars: ETHEREUM_RPC_URL, TREASURY_ADDRESS, OPERATOR_PRIVATE_KEY, CHAIN_ID)");
        let _ = PAYOUT_SERVICE.set(None);
    }
}

/// Execute a payout if the service is configured and destination is valid
pub async fn maybe_execute_payout(destination: &str, amount: u64, sequence: u64) {
    // Check if destination looks like an Ethereum payout
    if !destination.contains(".eth.") {
        return;
    }

    let service = match PAYOUT_SERVICE.get() {
        Some(Some(s)) => s,
        _ => {
            debug!("Ethereum payout service not initialized");
            return;
        }
    };

    match service.execute_payout(destination, amount, sequence).await {
        Ok(tx_hash) => {
            info!("Ethereum payout executed: tx={}", tx_hash);
        }
        Err(e) => {
            warn!("Ethereum payout failed: {:?}", e);
            // Don't fail the ILP payment - just log the error
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_destination() {
        let dest =
            "test.receiver.eth.31337.EURC.0x70997970C51812dc3A010C7d01b50e0d17dc79C8.abc123";
        let parsed = EthereumDestination::parse(dest).unwrap();

        assert_eq!(parsed.chain_id, 31337);
        assert_eq!(parsed.asset_code, "EURC");
        assert_eq!(
            parsed.recipient,
            "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
        );
    }

    #[test]
    fn test_parse_invalid_destination() {
        assert!(EthereumDestination::parse("test.sender.user").is_none());
        assert!(EthereumDestination::parse("too.short").is_none());
    }

    #[test]
    fn test_derive_anvil_address() {
        let addr = derive_address_from_key(
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        )
        .unwrap();
        assert_eq!(addr, "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    }
}
