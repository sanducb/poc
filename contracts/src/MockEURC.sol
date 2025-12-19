// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockEURC
 * @notice Mock ERC-20 token representing Euro Coin (EURC) for testing
 * @dev Decimals set to 6 to match real EURC
 */
contract MockEURC is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;

    constructor() ERC20("Mock Euro Coin", "EURC") Ownable(msg.sender) {}

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Mint tokens to an address (owner only)
     * @param to Recipient address
     * @param amount Amount to mint (in base units, 6 decimals)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from the caller's balance
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

