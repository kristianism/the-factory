// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {StandardNFTFactory} from "@standardNFT/StandardNFTFactory.sol";
import {StandardNFT} from "@standardNFT/StandardNFT.sol";

contract Common is Test {
    StandardNFTFactory public factory;
    StandardNFT public nft;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    address public beneficiary = makeAddr("beneficiary");
    address public collector = makeAddr("collector");

    function setUp() public virtual {
        // Deploy the protocol
        nft = new StandardNFT();
        factory = new StandardNFTFactory(
            address(nft),
            owner,
            collector,
            1 ether,
            5_000 // 50% referral rate
        );

        // Unpause the factory to allow NFT creation
        vm.prank(owner);
        factory.unpause();

        // Give user some ETH for testing
        vm.deal(user, 10e18);
    }
}
