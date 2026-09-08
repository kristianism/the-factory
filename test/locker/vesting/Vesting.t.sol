// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "./Common.sol";

contract VestingTest is Common {
    function test_initialization() public view {
        assertEq(factory.lockerImplementation(), address(vesting), "Locker implementation should match");
        assertEq(factory.feeCollector(), owner, "Fee Collector should be the owner");
        assertEq(factory.creationFee(), 1e18, "Creation fee should be 1 ETH");
        assertEq(factory.getTotalLockers(), 0, "Initial locker counter should be zero");
    }

    function test_createLocker_isNative() public returns (Vesting locker) {
        uint256 creationFee = factory.creationFee();
        uint256 ethAmount = 1e18; // 1 ETH
        uint64 startTimestamp = uint64(block.timestamp + 1 days);
        uint64 durationSeconds = 1 days;

        // Create a locker with native tokens
        vm.prank(user);
        locker = Vesting(
            factory.createLocker{value: creationFee + ethAmount}(
                startTimestamp, durationSeconds, true, address(0), ethAmount, beneficiary
            )
        );

        // Check the locker information
        assertEq(locker.start(), startTimestamp, "Start timestamp should match");
        assertEq(locker.duration(), durationSeconds, "Duration should match");
        assertEq(locker.owner(), user, "Locker owner should be the user");
        assertEq(address(locker).balance, 1e18, "Locker balance should be 1 ETH");
    }

    function test_createLocker_isNotNative() public returns (Vesting locker) {
        uint256 creationFee = factory.creationFee();
        uint256 tokenAmount = 1e18; // 1 token
        uint64 startTimestamp = uint64(block.timestamp + 1 days);
        uint64 durationSeconds = 1 days;
        token.mint(user, 10e18); // Mint tokens to user

        // Create a locker with ERC20 tokens
        vm.startPrank(user);
        token.approve(address(factory), 1e18); // Approve the factory to spend tokens
        locker = Vesting(
            factory.createLocker{value: creationFee}(
                startTimestamp, durationSeconds, false, address(token), tokenAmount, beneficiary
            )
        );
        vm.stopPrank();

        // Check the locker information
        assertEq(locker.start(), startTimestamp, "Start timestamp should match");
        assertEq(locker.duration(), durationSeconds, "Duration should match");
        assertEq(locker.owner(), user, "Locker owner should be the user");
        assertEq(token.balanceOf(address(locker)), 1e18, "Locker should hold 1 token");
    }

    function test_release_native() public {
        Vesting locker = test_createLocker_isNative(); // Create a locker first
        vm.warp(locker.start() + locker.duration() + 1 days); // Move time forward to release

        vm.prank(user);
        locker.release(); // Release the vested ETH

        uint256 userBalance = address(user).balance;
        assertEq(userBalance, (10e18 - factory.creationFee()), "User should receive the vested ETH");
    }

    function test_release_erc20() public {
        Vesting locker = test_createLocker_isNotNative(); // Create a locker first
        vm.warp(locker.start() + locker.duration() + 1 days); // Move time forward to release

        vm.prank(user);
        locker.release(address(token)); // Release the vested tokens

        uint256 userBalance = token.balanceOf(user);
        assertEq(userBalance, 10e18, "User should receive the vested tokens");
    }

    function test_setFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.prank(owner);
        factory.setFeeCollector(newFeeCollector);

        assertEq(factory.feeCollector(), newFeeCollector, "Fee Collector should be updated");
    }

    function test_setCreationFee() public {
        uint256 newFee = 2e18; // 2 ETH

        vm.prank(owner);
        factory.setCreationFee(newFee);

        assertEq(factory.creationFee(), newFee, "Creation fee should be updated");
    }

    function test_collectFees() public {
        test_createLocker_isNotNative(); // Create a locker to collect fees

        vm.startPrank(owner);

        if (factory.pendingFees() == 0) {
            vm.expectRevert();
            factory.collectFees();
        } else {
            factory.collectFees();
        }

        vm.stopPrank();

        uint256 feeCollectorBalance = address(factory.feeCollector()).balance;
        assertGt(feeCollectorBalance, 0, "Fee Collector should collect the creation fee");
    }

    function test_collectTokens() public {
        token.mint(address(factory), 10e18); // Mint tokens to the factory

        vm.prank(owner);
        factory.collectTokens(address(token));

        uint256 feeCollectorBalance = token.balanceOf(factory.feeCollector());
        assertEq(feeCollectorBalance, 10e18, "Fee Collector should collect the tokens");
    }
}
