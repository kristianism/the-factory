// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "@standardNFT/StandardNFT.sol";
import "@standardNFT/StandardNFTFactory.sol";

contract Deploy is Script {
    // Command line input
    // forge script script/DeployStandardNFT.sol \
    // --rpc-url $RPC_URL \
    // --etherscan-api-key $EXPLORER_API_KEY \
    // --verify -vvvv --slow --broadcast --interactives 1

    function run() external {
        vm.startBroadcast();

        address OWNER = vm.envAddress("OWNER");
        address COLLECTOR = vm.envAddress("COLLECTOR");

        StandardNFT nftImplementation = new StandardNFT();

        StandardNFTFactory factory = new StandardNFTFactory(
            address(nftImplementation), OWNER, COLLECTOR, vm.envUint("CREATION_FEE"), vm.envUint("REFERRAL_RATE")
        );

        // The configured owner explicitly unpauses after checking the deployment.

        console.log("NFT Implementation deployed at: ", address(nftImplementation));
        console.log("NFT Factory deployed at: ", address(factory));

        vm.stopBroadcast();
    }
}
