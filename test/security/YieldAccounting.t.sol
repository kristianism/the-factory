// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StandardYieldFarm} from "@standardYield/StandardYieldFarm.sol";

contract TestToken is ERC20 {
    bool public taxed;
    constructor() ERC20("Test", "TST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTaxed() external {
        taxed = true;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (taxed && from != address(0) && to != address(0)) {
            super._update(from, address(0), amount / 10);
            amount -= amount / 10;
        }
        super._update(from, to, amount);
    }
}

// Older ERC20s may successfully transfer without returning a boolean.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract YieldAccountingTest is Test {
    TestToken internal lp;
    TestToken internal reward;
    StandardYieldFarm internal farm;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal fees = makeAddr("fees");

    function setUp() public {
        lp = new TestToken();
        reward = new TestToken();
        farm = StandardYieldFarm(Clones.clone(address(new StandardYieldFarm())));
        farm.initialize(IERC20(address(reward)), address(this), fees, 1 ether, block.timestamp);
        farm.add(100, IERC20(address(lp)), 0, false);
        lp.mint(alice, 1000 ether);
        lp.mint(bob, 1000 ether);
        vm.prank(alice);
        lp.approve(address(farm), type(uint256).max);
        vm.prank(bob);
        lp.approve(address(farm), type(uint256).max);
    }

    function _deposit() internal {
        vm.prank(alice);
        farm.deposit(0, 100 ether);
    }

    function test_rejectsTaxedDepositsWithoutCreatingLiabilities() public {
        lp.setTaxed();
        vm.prank(alice);
        vm.expectRevert(StandardYieldFarm.UnsupportedToken.selector);
        farm.deposit(0, 100 ether);
        (uint256 amount,) = farm.userInfo(0, alice);
        assertEq(amount, 0);
        assertEq(lp.balanceOf(address(farm)), 0);
    }

    function test_donationsDoNotDiluteRewards() public {
        _deposit();
        lp.mint(address(farm), 900 ether);
        vm.warp(block.timestamp + 10);
        assertEq(farm.pendingReward(0, alice), 10 ether);
    }

    function test_shortfallSurvivesFullWithdrawalAndLaterFunding() public {
        _deposit();
        reward.mint(address(farm), 3 ether);
        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        farm.withdraw(0, 100 ether);
        assertEq(reward.balanceOf(alice), 3 ether);
        assertEq(farm.pendingReward(0, alice), 7 ether);
        assertEq(lp.balanceOf(alice), 1000 ether);
        reward.mint(address(farm), 7 ether);
        vm.prank(alice);
        farm.withdraw(0, 0);
        assertEq(reward.balanceOf(alice), 10 ether);
        assertEq(farm.pendingReward(0, alice), 0);
    }

    function test_zeroAllocationDoesNotDivideByZero() public {
        _deposit();
        farm.set(0, 0, 0, false);
        vm.warp(block.timestamp + 10);
        assertEq(farm.pendingReward(0, alice), 0);
        vm.prank(alice);
        farm.withdraw(0, 100 ether);
        assertEq(lp.balanceOf(alice), 1000 ether);
    }

    function test_rewardTokenCannotBeStakedAsPrincipal() public {
        vm.expectRevert(StandardYieldFarm.UnsupportedToken.selector);
        farm.add(1, IERC20(address(reward)), 0, false);
    }

    function test_allocationChangeCheckpointsOldRewardsEvenWithFalseFlag() public {
        _deposit();
        vm.warp(block.timestamp + 10);
        TestToken second = new TestToken();
        farm.add(100, IERC20(address(second)), 0, false);
        vm.warp(block.timestamp + 10);
        assertEq(farm.pendingReward(0, alice), 15 ether);
    }

    function test_emergencyExitDoesNotRedistributePastRewards() public {
        _deposit();
        vm.prank(bob);
        farm.deposit(0, 100 ether);
        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        farm.emergencyWithdraw(0);
        assertEq(farm.totalStaked(0), 100 ether);
        assertEq(farm.pendingReward(0, bob), 5 ether);
        assertEq(farm.pendingReward(0, alice), 0);
    }

    function test_noReturnRewardTokenCanPay() public {
        NoReturnToken token = new NoReturnToken();
        StandardYieldFarm other = StandardYieldFarm(Clones.clone(address(new StandardYieldFarm())));
        other.initialize(IERC20(address(token)), address(this), fees, 1 ether, block.timestamp);
        other.add(100, IERC20(address(lp)), 0, false);
        vm.startPrank(alice);
        lp.approve(address(other), 100 ether);
        other.deposit(0, 100 ether);
        vm.stopPrank();
        token.mint(address(other), 10 ether);
        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        other.withdraw(0, 100 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function testFuzz_principalMatchesCreditedDeposits(uint96 rawAmount, uint16 rawFee) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1000 ether);
        uint16 fee = uint16(bound(uint256(rawFee), 0, 10_000));
        farm.set(0, 100, fee, false);
        vm.prank(alice);
        farm.deposit(0, amount);
        uint256 credited = amount - amount * fee / 10_000;
        (uint256 recorded,) = farm.userInfo(0, alice);
        assertEq(recorded, credited);
        assertEq(farm.totalStaked(0), credited);
        assertEq(lp.balanceOf(address(farm)), credited);
        vm.prank(alice);
        farm.withdraw(0, credited);
        assertEq(farm.totalStaked(0), 0);
    }
}

contract CallbackStakeToken is ERC20 {
    StandardYieldFarm public farm;
    bool public callbackBlocked;
    constructor() ERC20("Callback", "CALL") {}

    function setFarm(StandardYieldFarm target) external {
        farm = target;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to == address(farm)) {
            (bool success,) = address(farm).call(abi.encodeCall(StandardYieldFarm.updatePool, (0)));
            callbackBlocked = !success;
        }
        super._update(from, to, value);
    }
}

contract CallbackProtectionTest is Test {
    function test_stakeCallbackCannotChangePoolAccounting() public {
        TestToken reward = new TestToken();
        CallbackStakeToken stake = new CallbackStakeToken();
        StandardYieldFarm farm = StandardYieldFarm(Clones.clone(address(new StandardYieldFarm())));
        farm.initialize(IERC20(address(reward)), address(this), address(0x1234), 1 ether, block.timestamp);
        farm.add(100, IERC20(address(stake)), 0, false);
        stake.setFarm(farm);
        stake.mint(address(this), 100 ether);
        stake.approve(address(farm), 100 ether);
        farm.deposit(0, 100 ether);
        assertTrue(stake.callbackBlocked());
        assertEq(farm.totalStaked(0), 100 ether);
    }
}
