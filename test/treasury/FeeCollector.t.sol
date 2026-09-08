// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {FeeCollector} from "@treasury/FeeCollector.sol";
import {MockFactory} from "./mocks/MockFactory.sol";

contract FeeCollectorTest is Test {
    FeeCollector internal collector;
    FeeCollector internal implementation;
    address internal treasury = makeAddr("treasury");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        implementation = new FeeCollector();
        collector = FeeCollector(
            payable(address(
                    new ERC1967Proxy(
                        address(implementation), abi.encodeCall(FeeCollector.initialize, (address(this), treasury))
                    )
                ))
        );
    }

    function test_collectSkipsFailureAndPaysTreasury() public {
        MockFactory good = new MockFactory(address(collector));
        MockFactory bad = new MockFactory(outsider);
        vm.deal(address(good), 2 ether);
        vm.deal(address(bad), 3 ether);
        address[] memory factories = new address[](2);
        factories[0] = address(bad);
        factories[1] = address(good);
        collector.collectFees(factories);
        assertEq(treasury.balance, 2 ether);
        assertEq(address(bad).balance, 3 ether);
    }

    function test_implementationAndProxyCannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(outsider, outsider);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        collector.initialize(outsider, outsider);
    }

    function test_onlyOwnerCanCollectOrUpgrade() public {
        FeeCollector next = new FeeCollector();
        vm.prank(outsider);
        vm.expectRevert();
        collector.collectEth();
        vm.prank(outsider);
        vm.expectRevert();
        collector.upgradeToAndCall(address(next), "");
        collector.upgradeToAndCall(address(next), "");
        assertEq(collector.owner(), address(this));
        assertEq(collector.treasury(), treasury);
    }
}
