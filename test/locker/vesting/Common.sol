// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@vesting/Vesting.sol";
import "@vesting/VestingFactory.sol";
import "./mocks/MockERC20.sol";

contract Common is Test {
    VestingFactory public factory;
    Vesting public vesting;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public beneficiary = makeAddr("beneficiary");

    function setUp() public virtual {
        // Deploy the mock ERC20 token
        token = new MockERC20("MockToken", "MOCK", 1e24); // 1 million tokens with 18 decimals

        // Deploy the protocol
        vesting = new Vesting();
        factory = new VestingFactory(address(vesting), owner, owner, 1e18, 5_000); // 1 ETH creation fee

        // Unpause the factory to allow locker creation
        vm.prank(owner);
        factory.unpause();

        // Give user some ETH for testing
        vm.deal(user, 10e18); // 10 ETH to user
    }
}
