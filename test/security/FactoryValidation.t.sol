// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {StandardERC20} from "@standardERC20/StandardERC20.sol";
import {StandardERC20Factory} from "@standardERC20/StandardERC20Factory.sol";
import {StandardNFT} from "@standardNFT/StandardNFT.sol";
import {StandardNFTFactory} from "@standardNFT/StandardNFTFactory.sol";
import {TaxToken} from "@taxToken/TaxToken.sol";
import {TaxTokenFactory} from "@taxToken/TaxTokenFactory.sol";
import {Vesting} from "@vesting/Vesting.sol";
import {VestingFactory} from "@vesting/VestingFactory.sol";
import {RegistrationAirdrop} from "@airdrop/RegistrationAirdrop.sol";
import {RegistrationAirdropFactory} from "@airdrop/RegistrationAirdropFactory.sol";
import {StandardYieldFarm} from "@standardYield/StandardYieldFarm.sol";
import {StandardYieldFarmFactory} from "@standardYield/StandardYieldFarmFactory.sol";
import {CommonErrors} from "@common/CommonErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract RejectingReferral {
    receive() external payable {
        revert();
    }
}

contract FactoryValidationTest is Test {
    address internal user = makeAddr("user");
    receive() external payable {}

    function test_allFactoriesRejectImplementationWithoutCode() public {
        vm.expectRevert(CommonErrors.InvalidImplementationAddress.selector);
        new StandardERC20Factory(user, address(this), address(this), 0);
        vm.expectRevert(CommonErrors.InvalidImplementationAddress.selector);
        new StandardNFTFactory(user, address(this), address(this), 0, 0);
        vm.expectRevert(CommonErrors.InvalidImplementationAddress.selector);
        new TaxTokenFactory(user, address(this), address(this), 0);
        vm.expectRevert(CommonErrors.InvalidImplementationAddress.selector);
        new RegistrationAirdropFactory(user, address(this), address(this), 0);
        vm.expectRevert(CommonErrors.InvalidImplementationAddress.selector);
        new VestingFactory(user, address(this), address(this), 0, 0);
        vm.expectRevert(CommonErrors.InvalidImplementationAddress.selector);
        new StandardYieldFarmFactory(user, address(this), address(this), 0);
    }

    function test_allRegistriesRejectZeroAddress() public {
        assertFalse(
            (new StandardERC20Factory(address(new StandardERC20()), address(this), address(this), 0))
            .isValidToken(address(0))
        );
        assertFalse(
            (new StandardNFTFactory(address(new StandardNFT()), address(this), address(this), 0, 0))
            .isValidNFT(address(0))
        );
        assertFalse(
            (new TaxTokenFactory(address(new TaxToken()), address(this), address(this), 0)).isValidTaxToken(address(0))
        );
        assertFalse(
            (new RegistrationAirdropFactory(address(new RegistrationAirdrop()), address(this), address(this), 0))
            .isValidAirdrop(address(0))
        );
        assertFalse(
            (new VestingFactory(address(new Vesting()), address(this), address(this), 0, 0)).isValidLocker(address(0))
        );
        assertFalse(
            (new StandardYieldFarmFactory(address(new StandardYieldFarm()), address(this), address(this), 0))
            .isValidYieldFarm(address(0))
        );
    }

    function test_nftRejectsEmptyFields() public {
        StandardNFTFactory factory =
            new StandardNFTFactory(address(new StandardNFT()), address(this), address(this), 0, 0);
        factory.unpause();
        vm.expectRevert(CommonErrors.InputCannotBeNull.selector);
        factory.createNFT("", "N", "ipfs://", address(0));
        vm.expectRevert(CommonErrors.InputCannotBeNull.selector);
        factory.createNFT("Name", "", "ipfs://", address(0));
        vm.expectRevert(CommonErrors.InputCannotBeNull.selector);
        factory.createNFT("Name", "N", "", address(0));
    }

    function test_vestingCannotPaySelfReferral() public {
        VestingFactory factory = new VestingFactory(address(new Vesting()), address(this), address(this), 1 ether, 5000);
        factory.unpause();
        vm.deal(user, 3 ether);
        vm.prank(user);
        factory.createLocker{value: 2 ether}(uint64(block.timestamp + 1), 100, true, address(0), 1 ether, user);
        assertEq(user.balance, 1 ether);
        assertEq(address(factory).balance, 1 ether);
    }

    function test_yieldFactoryFeesCanBeCollected() public {
        StandardYieldFarmFactory factory =
            new StandardYieldFarmFactory(address(new StandardYieldFarm()), address(this), address(this), 1 ether);
        factory.unpause();
        vm.deal(user, 1 ether);
        vm.prank(user);
        factory.createYieldFarm{value: 1 ether}(IERC20(address(new StandardERC20())), user, 0, block.timestamp);
        uint256 beforeBalance = address(this).balance;
        factory.collectFees();
        assertEq(address(this).balance, beforeBalance + 1 ether);
        assertEq(factory.pendingFees(), 0);
    }

    function test_rejectedReferralDoesNotBlockCreation() public {
        StandardNFTFactory factory =
            new StandardNFTFactory(address(new StandardNFT()), address(this), address(this), 1 ether, 5000);
        factory.unpause();
        RejectingReferral referrer = new RejectingReferral();
        vm.deal(user, 2 ether);
        vm.prank(user);
        address nft = factory.createNFT{value: 2 ether}("Name", "N", "ipfs://", address(referrer));
        assertTrue(factory.isValidNFT(nft));
        assertEq(address(factory).balance, 1 ether);
        assertEq(user.balance, 1 ether);
    }

    function test_factoryOwnershipRequiresAcceptance() public {
        StandardERC20Factory factory =
            new StandardERC20Factory(address(new StandardERC20()), address(this), address(this), 0);
        factory.transferOwnership(user);
        assertEq(factory.owner(), address(this));
        vm.prank(user);
        factory.acceptOwnership();
        assertEq(factory.owner(), user);
    }

    function test_taxMintAndTransferSupportFullUintSupply() public {
        TaxToken token = TaxToken(Clones.clone(address(new TaxToken())));
        token.initialize("Full", "FULL", type(uint256).max, 2000, makeAddr("beneficiary"), address(this));
        token.transfer(user, type(uint256).max);
        vm.prank(user);
        token.transfer(makeAddr("recipient"), type(uint256).max);
        assertEq(token.totalSupply(), type(uint256).max);
    }
}
