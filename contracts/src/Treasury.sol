// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Treasury
 * @notice Prefunded vault for ILP-triggered ERC-20 payouts
 * @dev Implements idempotent payouts using payment IDs
 * 
 * Key features:
 * - Prefunded with ERC-20 tokens (e.g. EURC)
 * - Only authorized operators can trigger payouts
 * - Idempotent: each payment ID can only be used once
 * - No double payouts even if the same request is replayed
 */
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The ERC-20 token used for payouts
    IERC20 public immutable payoutToken;

    /// @notice Mapping of addresses that can execute payouts
    mapping(address => bool) public operators;

    /// @notice Mapping of payment IDs that have been used
    mapping(bytes32 => bool) public usedPaymentIds;

    /// @notice Emitted when a payout is executed
    event PayoutExecuted(
        bytes32 indexed paymentId,
        address indexed recipient,
        uint256 amount,
        address indexed operator
    );

    /// @notice Emitted when an operator is added
    event OperatorAdded(address indexed operator);

    /// @notice Emitted when an operator is removed
    event OperatorRemoved(address indexed operator);

    /// @notice Error thrown when a non-operator tries to execute a payout
    error NotOperator();

    /// @notice Error thrown when payment ID was already used
    error PaymentIdAlreadyUsed(bytes32 paymentId);

    /// @notice Error thrown when payout amount is zero
    error ZeroAmount();

    /// @notice Error thrown when recipient is zero address
    error ZeroAddress();

    /// @notice Error thrown when treasury has insufficient balance
    error InsufficientBalance(uint256 requested, uint256 available);

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert NotOperator();
        _;
    }

    /**
     * @notice Create a new Treasury
     * @param _payoutToken Address of the ERC-20 token for payouts
     */
    constructor(address _payoutToken) Ownable(msg.sender) {
        if (_payoutToken == address(0)) revert ZeroAddress();
        payoutToken = IERC20(_payoutToken);
        
        // Owner is automatically an operator
        operators[msg.sender] = true;
        emit OperatorAdded(msg.sender);
    }

    /**
     * @notice Add an operator
     * @param operator Address to add as operator
     */
    function addOperator(address operator) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        operators[operator] = true;
        emit OperatorAdded(operator);
    }

    /**
     * @notice Remove an operator
     * @param operator Address to remove as operator
     */
    function removeOperator(address operator) external onlyOwner {
        operators[operator] = false;
        emit OperatorRemoved(operator);
    }

    /**
     * @notice Execute a payout to a user
     * @dev Idempotent: if paymentId was already used, the call reverts
     * @param paymentId Unique identifier for this payment (prevents double-spend)
     * @param to Recipient address
     * @param amount Amount to transfer (in token base units)
     */
    function payoutToUser(
        bytes32 paymentId,
        address to,
        uint256 amount
    ) external onlyOperator nonReentrant {
        // Validate inputs
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        
        // Check idempotency
        if (usedPaymentIds[paymentId]) revert PaymentIdAlreadyUsed(paymentId);

        // Check balance
        uint256 balance = payoutToken.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(amount, balance);

        // Mark payment ID as used BEFORE transfer (checks-effects-interactions)
        usedPaymentIds[paymentId] = true;

        // Execute transfer
        payoutToken.safeTransfer(to, amount);

        emit PayoutExecuted(paymentId, to, amount, msg.sender);
    }

    /**
     * @notice Check if a payment ID has been used
     * @param paymentId The payment ID to check
     * @return True if the payment ID has been used
     */
    function isPaymentIdUsed(bytes32 paymentId) external view returns (bool) {
        return usedPaymentIds[paymentId];
    }

    /**
     * @notice Get the current balance of the treasury
     * @return The balance in token base units
     */
    function getBalance() external view returns (uint256) {
        return payoutToken.balanceOf(address(this));
    }

    /**
     * @notice Withdraw tokens from the treasury (owner only)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        payoutToken.safeTransfer(to, amount);
    }
}

