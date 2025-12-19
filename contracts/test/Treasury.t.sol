// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockEURC.sol";
import "../src/Treasury.sol";

contract TreasuryTest is Test {
    MockEURC public eurc;
    Treasury public treasury;
    
    // Mirror event for testing
    event PayoutExecuted(bytes32 indexed paymentId, address indexed to, uint256 amount, address indexed operator);
    
    address public owner = address(1);
    address public operator = address(2);
    address public recipient = address(3);
    address public notOperator = address(4);
    
    uint256 constant PREFUND_AMOUNT = 1_000_000 * 1e6; // 1M EURC
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy EURC
        eurc = new MockEURC();
        
        // Deploy Treasury
        treasury = new Treasury(address(eurc));
        
        // Prefund Treasury
        eurc.mint(address(treasury), PREFUND_AMOUNT);
        
        // Add operator
        treasury.addOperator(operator);
        
        vm.stopPrank();
    }
    
    function testInitialState() public view {
        assertEq(treasury.getBalance(), PREFUND_AMOUNT);
        assertTrue(treasury.operators(owner));
        assertTrue(treasury.operators(operator));
        assertFalse(treasury.operators(notOperator));
    }
    
    function testSuccessfulPayout() public {
        bytes32 paymentId = keccak256("payment-1");
        uint256 amount = 1000 * 1e6; // 1000 EURC
        
        vm.prank(operator);
        treasury.payoutToUser(paymentId, recipient, amount);
        
        assertEq(eurc.balanceOf(recipient), amount);
        assertEq(treasury.getBalance(), PREFUND_AMOUNT - amount);
        assertTrue(treasury.isPaymentIdUsed(paymentId));
    }
    
    function testIdempotency() public {
        bytes32 paymentId = keccak256("payment-2");
        uint256 amount = 500 * 1e6;
        
        // First payout succeeds
        vm.prank(operator);
        treasury.payoutToUser(paymentId, recipient, amount);
        
        // Second payout with same ID fails
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Treasury.PaymentIdAlreadyUsed.selector, paymentId));
        treasury.payoutToUser(paymentId, recipient, amount);
        
        // Balance should only reflect one payout
        assertEq(eurc.balanceOf(recipient), amount);
    }
    
    function testOnlyOperator() public {
        bytes32 paymentId = keccak256("payment-3");
        uint256 amount = 100 * 1e6;
        
        vm.prank(notOperator);
        vm.expectRevert(Treasury.NotOperator.selector);
        treasury.payoutToUser(paymentId, recipient, amount);
    }
    
    function testZeroAmount() public {
        bytes32 paymentId = keccak256("payment-4");
        
        vm.prank(operator);
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.payoutToUser(paymentId, recipient, 0);
    }
    
    function testZeroAddress() public {
        bytes32 paymentId = keccak256("payment-5");
        uint256 amount = 100 * 1e6;
        
        vm.prank(operator);
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.payoutToUser(paymentId, address(0), amount);
    }
    
    function testInsufficientBalance() public {
        bytes32 paymentId = keccak256("payment-6");
        uint256 amount = PREFUND_AMOUNT + 1; // More than available
        
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(
            Treasury.InsufficientBalance.selector, 
            amount, 
            PREFUND_AMOUNT
        ));
        treasury.payoutToUser(paymentId, recipient, amount);
    }
    
    function testAddRemoveOperator() public {
        address newOperator = address(5);
        
        // Add operator
        vm.prank(owner);
        treasury.addOperator(newOperator);
        assertTrue(treasury.operators(newOperator));
        
        // Remove operator
        vm.prank(owner);
        treasury.removeOperator(newOperator);
        assertFalse(treasury.operators(newOperator));
    }
    
    function testWithdraw() public {
        uint256 withdrawAmount = 100 * 1e6;
        
        vm.prank(owner);
        treasury.withdraw(owner, withdrawAmount);
        
        assertEq(eurc.balanceOf(owner), withdrawAmount);
        assertEq(treasury.getBalance(), PREFUND_AMOUNT - withdrawAmount);
    }
    
    function testOwnerCannotWithdrawToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.withdraw(address(0), 100);
    }
    
    function testMultiplePayouts() public {
        uint256 amount1 = 100 * 1e6;
        uint256 amount2 = 200 * 1e6;
        uint256 amount3 = 300 * 1e6;
        
        vm.startPrank(operator);
        
        treasury.payoutToUser(keccak256("p1"), recipient, amount1);
        treasury.payoutToUser(keccak256("p2"), recipient, amount2);
        treasury.payoutToUser(keccak256("p3"), recipient, amount3);
        
        vm.stopPrank();
        
        assertEq(eurc.balanceOf(recipient), amount1 + amount2 + amount3);
        assertEq(treasury.getBalance(), PREFUND_AMOUNT - amount1 - amount2 - amount3);
    }
    
    function testPayoutEvent() public {
        bytes32 paymentId = keccak256("event-test");
        uint256 amount = 50 * 1e6;
        
        vm.prank(operator);
        vm.expectEmit(true, true, true, true);
        emit PayoutExecuted(paymentId, recipient, amount, operator);
        treasury.payoutToUser(paymentId, recipient, amount);
    }
}

