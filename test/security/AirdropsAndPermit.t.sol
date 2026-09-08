// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {RegistrationAirdrop} from "@airdrop/RegistrationAirdrop.sol";
import {MerkleAirdrop} from "@airdrop/MerkleAirdrop.sol";
import {StandardERC20} from "@standardERC20/StandardERC20.sol";
import {CommonErrors} from "@common/CommonErrors.sol";
import {Vesting} from "@vesting/Vesting.sol";
import {TestToken} from "./YieldAccounting.t.sol";

contract AirdropsAndPermitTest is Test {
    TestToken internal token;
    RegistrationAirdrop internal airdrop;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    receive() external payable {}

    function setUp() public {
        token = new TestToken();
        airdrop = RegistrationAirdrop(Clones.clone(address(new RegistrationAirdrop())));
        airdrop.initialize(address(token), 10 ether, address(this));
        airdrop.setRegistrationStatus(true);
    }

    function test_registrationCannotExceedFunding() public {
        token.mint(address(airdrop), 10 ether);
        vm.prank(alice);
        airdrop.register();
        vm.prank(bob);
        vm.expectRevert(CommonErrors.InsufficientFunds.selector);
        airdrop.register();
        assertEq(airdrop.getTotalRegistered(), 1);
    }

    function test_onlyUnallocatedSurplusCanBeWithdrawn() public {
        token.mint(address(airdrop), 15 ether);
        vm.prank(alice);
        airdrop.register();
        vm.expectRevert(CommonErrors.InsufficientFunds.selector);
        airdrop.withdrawToken(6 ether);
        airdrop.withdrawToken(5 ether);
        airdrop.setClaimingStatus(true);
        vm.prank(alice);
        airdrop.claim();
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(airdrop.totalClaimed(), 10 ether);
        vm.prank(alice);
        vm.expectRevert(RegistrationAirdrop.AlreadyClaimed.selector);
        airdrop.claim();
    }

    function test_batchFundingFailureRollsBackEveryRegistration() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 10 ether;
        token.mint(address(airdrop), 10 ether);
        vm.expectRevert(CommonErrors.InsufficientFunds.selector);
        airdrop.batchRegister(accounts, amounts);
        assertEq(airdrop.getTotalRegistered(), 0);
    }

    function test_batchRejectsZeroAddressAndZeroAllocation() public {
        address[] memory accounts = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        airdrop.batchRegister(accounts, amounts);
        accounts[0] = alice;
        amounts[0] = 0;
        vm.expectRevert(CommonErrors.ZeroAmount.selector);
        airdrop.batchRegister(accounts, amounts);
    }

    function test_paginationAcceptsMaximumLimit() public {
        token.mint(address(airdrop), 20 ether);
        vm.prank(alice);
        airdrop.register();
        vm.prank(bob);
        airdrop.register();
        address[] memory page = airdrop.getRegisteredUsers(1, type(uint256).max);
        assertEq(page.length, 1);
        assertEq(page[0], bob);
    }

    function test_merkleProofBindsRecipientAndAmountAndCannotReplay() public {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(alice, uint256(10 ether)))));
        MerkleAirdrop merkle = new MerkleAirdrop(leaf, address(token), address(this));
        token.mint(address(merkle), 10 ether);
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(bob);
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        merkle.claim(proof, 10 ether);
        vm.prank(alice);
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        merkle.claim(proof, 11 ether);
        vm.prank(alice);
        merkle.claim(proof, 10 ether);
        vm.prank(alice);
        vm.expectRevert(MerkleAirdrop.AlreadyClaimed.selector);
        merkle.claim(proof, 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_permitRejectsReplayAndWrongCloneDomain() public {
        uint256 key = 12345;
        address holder = vm.addr(key);
        StandardERC20 implementation = new StandardERC20();
        StandardERC20 first = StandardERC20(Clones.clone(address(implementation)));
        StandardERC20 second = StandardERC20(Clones.clone(address(implementation)));
        first.initialize("Token", "TOK", 100 ether, holder);
        second.initialize("Token", "TOK", 100 ether, holder);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                holder,
                alice,
                uint256(10 ether),
                uint256(0),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", first.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        vm.expectRevert();
        second.permit(holder, alice, 10 ether, deadline, v, r, s);
        first.permit(holder, alice, 10 ether, deadline, v, r, s);
        assertEq(first.allowance(holder, alice), 10 ether);
        vm.expectRevert();
        first.permit(holder, alice, 10 ether, deadline, v, r, s);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        first.initialize("Again", "NO", 1, alice);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize("Again", "NO", 1, alice);
    }

    function test_vestingReleaseAlwaysPaysBeneficiaryAndRenounceIsBlocked() public {
        Vesting wallet = Vesting(payable(Clones.clone(address(new Vesting()))));
        wallet.initialize(address(this), uint64(block.timestamp + 1), 0);
        token.mint(address(wallet), 10 ether);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        wallet.release(address(token));
        assertEq(token.balanceOf(address(this)), 10 ether);
        assertEq(token.balanceOf(alice), 0);
        vm.expectRevert("Vesting ownership cannot be renounced");
        wallet.renounceOwnership();
    }
}
