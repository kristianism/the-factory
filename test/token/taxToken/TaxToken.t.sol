// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {TaxToken} from "@taxToken/TaxToken.sol";
import {TaxTokenFactory} from "@taxToken/TaxTokenFactory.sol";

contract TaxTokenTest is Test {
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public taxBeneficiary = makeAddr("taxBeneficiary");
    address public feeCollector = makeAddr("feeCollector");

    string constant TOKEN_NAME = "Test Token";
    string constant TOKEN_SYMBOL = "TTK";

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1 million tokens with 18 decimals
    uint256 constant TRANSFER_AMOUNT = 1_000 * 10 ** 18; // 1 thousand tokens with 18 decimals
    uint256 constant TRANSFER_TAX_RATE = 500; // 5% tax rate in basis points
    uint256 constant MINT_AMOUNT = 1_000 * 10 ** 18; // 1 thousand tokens with 18 decimals
    uint256 constant CREATION_FEE = 1 ether; // 1 ether creation fee

    TaxToken public taxToken;
    TaxTokenFactory public taxTokenFactory;

    TaxToken public tokenA;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(user, 10 ether);

        vm.startPrank(owner);

        // Initialize the contracts
        taxToken = new TaxToken();
        taxTokenFactory = new TaxTokenFactory(address(taxToken), owner, feeCollector, CREATION_FEE);

        // Unpause the factory to allow token creation
        taxTokenFactory.unpause();

        // Create a new TaxToken using the factory
        tokenA = TaxToken(
            taxTokenFactory.createToken{value: CREATION_FEE}(
                TOKEN_NAME, TOKEN_SYMBOL, INITIAL_SUPPLY, TRANSFER_TAX_RATE, taxBeneficiary, address(0)
            )
        );

        vm.stopPrank();
    }

    function test_initialization() public view {
        // Check the token name and symbol
        assertEq(tokenA.name(), TOKEN_NAME, "Token name mismatch");
        assertEq(tokenA.symbol(), TOKEN_SYMBOL, "Token symbol mismatch");

        // Check the initial supply
        assertEq(tokenA.totalSupply(), INITIAL_SUPPLY, "Initial supply mismatch");
        assertEq(tokenA.balanceOf(owner), INITIAL_SUPPLY, "User balance mismatch");

        // Check the transfer tax rate
        assertEq(tokenA.transferTaxRate(), TRANSFER_TAX_RATE, "Transfer tax rate mismatch");

        // Check the tax beneficiary address
        assertEq(tokenA.taxBeneficiary(), taxBeneficiary, "Tax beneficiary address mismatch");

        // Check No Tax Receipient and Sender
        assertTrue(tokenA.noTaxRecipient(owner), "User should be a no tax recipient");
        assertTrue(tokenA.noTaxSender(owner), "User should be a no tax sender");
    }

    function test_mint() public {
        vm.startPrank(owner);

        // Mint tokens to the user
        tokenA.mint(owner, MINT_AMOUNT);
        assertEq(tokenA.balanceOf(owner), INITIAL_SUPPLY + MINT_AMOUNT, "Minting failed");

        vm.stopPrank();
    }

    function test_mint_revertsOnZeroAddress() public {
        vm.startPrank(owner);

        // Attempt to mint tokens to the zero address
        vm.expectRevert();
        tokenA.mint(address(0), MINT_AMOUNT);

        vm.stopPrank();
    }

    function test_mint_revertsOnZeroAmount() public {
        vm.startPrank(owner);

        // Attempt to mint zero tokens
        vm.expectRevert();
        tokenA.mint(owner, 0);

        vm.stopPrank();
    }

    function test_mint_revertsOnNonOwner() public {
        vm.startPrank(user);

        // Attempt to mint tokens as a non-owner
        vm.expectRevert();
        tokenA.mint(user, MINT_AMOUNT);

        vm.stopPrank();
    }

    function test_burn() public {
        vm.startPrank(owner);

        // Burn tokens from the user
        tokenA.burn(INITIAL_SUPPLY);
        assertEq(tokenA.balanceOf(owner), 0, "Burning failed");

        vm.stopPrank();
    }

    function test_burn_revertsOnZeroAmount() public {
        vm.startPrank(owner);

        // Attempt to burn zero tokens
        vm.expectRevert();
        tokenA.burn(0);

        vm.stopPrank();
    }

    function test_burn_revertsOnAmountGreaterThanBalance() public {
        vm.startPrank(owner);

        // Attempt to burn more tokens than balance
        vm.expectRevert();
        tokenA.burn(INITIAL_SUPPLY + 1);

        vm.stopPrank();
    }

    function test_transfer_withNoTax() public {
        vm.startPrank(owner);

        // Transfer tokens to the user with no tax
        tokenA.transfer(user, TRANSFER_AMOUNT);
        assertEq(tokenA.balanceOf(owner), INITIAL_SUPPLY - TRANSFER_AMOUNT, "Transfer failed");
        assertEq(tokenA.balanceOf(user), TRANSFER_AMOUNT, "User balance mismatch after transfer");

        vm.stopPrank();
    }

    function test_transfer_withTax() public {
        vm.startPrank(owner);

        // Remove owner from no tax sender list
        tokenA.setNoTaxSenderAddr(owner, false);

        // Transfer tokens to the user with tax
        uint256 taxAmount = (TRANSFER_AMOUNT * TRANSFER_TAX_RATE) / 10000;
        uint256 netAmount = TRANSFER_AMOUNT - taxAmount;

        tokenA.transfer(user, TRANSFER_AMOUNT);

        assertEq(tokenA.balanceOf(owner), INITIAL_SUPPLY - TRANSFER_AMOUNT, "Transfer failed");
        assertEq(tokenA.balanceOf(user), netAmount, "User balance mismatch after transfer with tax");
        assertEq(
            tokenA.balanceOf(taxBeneficiary), taxAmount, "Tax beneficiary balance mismatch after transfer with tax"
        );

        vm.stopPrank();
    }

    function test_updateTransferTaxRate() public {
        vm.startPrank(owner);

        // Update the transfer tax rate
        uint256 newTaxRate = 1_000; // 10% tax rate in basis points

        tokenA.updateTransferTaxRate(newTaxRate);
        assertEq(tokenA.transferTaxRate(), newTaxRate, "Transfer tax rate update failed");

        vm.stopPrank();
    }

    function test_updateTransferTaxRate_revertsOnExceedingMax() public {
        vm.startPrank(owner);

        // Attempt to update the transfer tax rate to exceed the maximum
        vm.expectRevert();
        tokenA.updateTransferTaxRate(10_001); // 100.01% tax rate in basis points

        vm.stopPrank();
    }

    function test_updateTransferTaxRate_revertsOnNonOwner() public {
        vm.startPrank(user);

        // Attempt to update the transfer tax rate as a non-owner
        vm.expectRevert();
        tokenA.updateTransferTaxRate(1_000); // 10% tax rate in basis points

        vm.stopPrank();
    }

    function test_updateTaxBeneficiary() public {
        vm.startPrank(owner);

        // Update the tax beneficiary address
        address newTaxBeneficiary = makeAddr("newTaxBeneficiary");
        tokenA.updateTaxBeneficiary(newTaxBeneficiary);

        assertEq(tokenA.taxBeneficiary(), newTaxBeneficiary, "Tax beneficiary update failed");
        assertTrue(tokenA.noTaxRecipient(newTaxBeneficiary), "New tax beneficiary should be a no tax recipient");
        assertTrue(tokenA.noTaxSender(newTaxBeneficiary), "New tax beneficiary should be a no tax sender");

        vm.stopPrank();
    }

    function test_updateTaxBeneficiary_revertsOnZeroAddress() public {
        vm.startPrank(owner);

        // Attempt to update the tax beneficiary to the zero address
        vm.expectRevert();
        tokenA.updateTaxBeneficiary(address(0));

        vm.stopPrank();
    }

    function test_updateTaxBeneficiary_revertsOnNonOwner() public {
        vm.startPrank(user);

        // Attempt to update the tax beneficiary as a non-owner
        vm.expectRevert();
        tokenA.updateTaxBeneficiary(makeAddr("newTaxBeneficiary"));

        vm.stopPrank();
    }

    function test_setNoTaxSenderAddr() public {
        vm.startPrank(owner);

        // Set the user as a no tax sender
        tokenA.setNoTaxSenderAddr(user, true);
        assertTrue(tokenA.noTaxSender(user), "User should be a no tax sender");

        // Remove the user from no tax sender list
        tokenA.setNoTaxSenderAddr(user, false);
        assertFalse(tokenA.noTaxSender(user), "User should not be a no tax sender");

        vm.stopPrank();
    }

    function test_setNoTaxSenderAddr_revertsOnZeroAddress() public {
        vm.startPrank(owner);

        // Attempt to set the zero address as a no tax sender
        vm.expectRevert();
        tokenA.setNoTaxSenderAddr(address(0), true);

        vm.stopPrank();
    }

    function test_setNoTaxSenderAddr_revertsOnNonOwner() public {
        vm.startPrank(user);

        // Attempt to set the user as a no tax sender as a non-owner
        vm.expectRevert();
        tokenA.setNoTaxSenderAddr(user, true);

        vm.stopPrank();
    }

    function test_setNoTaxRecipientAddr() public {
        vm.startPrank(owner);

        // Set the user as a no tax recipient
        tokenA.setNoTaxRecipientAddr(user, true);
        assertTrue(tokenA.noTaxRecipient(user), "User should be a no tax recipient");

        // Remove the user from no tax recipient list
        tokenA.setNoTaxRecipientAddr(user, false);
        assertFalse(tokenA.noTaxRecipient(user), "User should not be a no tax recipient");

        vm.stopPrank();
    }

    function test_setNoTaxRecipientAddr_revertsOnZeroAddress() public {
        vm.startPrank(owner);

        // Attempt to set the zero address as a no tax recipient
        vm.expectRevert();
        tokenA.setNoTaxRecipientAddr(address(0), true);

        vm.stopPrank();
    }

    function test_setNoTaxRecipientAddr_revertsOnNonOwner() public {
        vm.startPrank(user);

        // Attempt to set the user as a no tax recipient as a non-owner
        vm.expectRevert();
        tokenA.setNoTaxRecipientAddr(user, true);

        vm.stopPrank();
    }
}
