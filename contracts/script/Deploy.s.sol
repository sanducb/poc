// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MockEURC.sol";
import "../src/Treasury.sol";

/**
 * @title Deploy
 * @notice Deployment script for MockEURC and Treasury contracts
 * 
 * Usage:
 *   forge script script/Deploy.s.sol:Deploy --rpc-url anvil --broadcast
 * 
 * Environment variables:
 *   PRIVATE_KEY - Deployer private key (defaults to Anvil's first account)
 *   PREFUND_AMOUNT - Amount of EURC to prefund treasury (defaults to 1,000,000 EURC)
 *   OPERATOR_ADDRESS - Additional operator address (optional)
 */
contract Deploy is Script {
    // Default prefund amount: 1,000,000 EURC (with 6 decimals)
    uint256 constant DEFAULT_PREFUND = 1_000_000 * 1e6;

    function run() external {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get prefund amount
        uint256 prefundAmount = vm.envOr("PREFUND_AMOUNT", DEFAULT_PREFUND);
        
        // Optional additional operator
        address operatorAddress = vm.envOr("OPERATOR_ADDRESS", address(0));

        console.log("Deployer:", deployer);
        console.log("Prefund amount:", prefundAmount);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockEURC
        MockEURC eurc = new MockEURC();
        console.log("MockEURC deployed at:", address(eurc));

        // Deploy Treasury
        Treasury treasury = new Treasury(address(eurc));
        console.log("Treasury deployed at:", address(treasury));

        // Mint EURC to Treasury
        eurc.mint(address(treasury), prefundAmount);
        console.log("Minted", prefundAmount, "EURC to Treasury");

        // Add additional operator if specified
        if (operatorAddress != address(0)) {
            treasury.addOperator(operatorAddress);
            console.log("Added operator:", operatorAddress);
        }

        vm.stopBroadcast();

        // Output deployment info as JSON
        string memory json = string(abi.encodePacked(
            '{"eurc":"', vm.toString(address(eurc)),
            '","treasury":"', vm.toString(address(treasury)),
            '","prefundAmount":"', vm.toString(prefundAmount),
            '","chainId":"', vm.toString(block.chainid),
            '"}'
        ));
        
        // Write to file
        vm.writeFile("./addresses.json", json);
        console.log("\nAddresses written to addresses.json");
    }
}

