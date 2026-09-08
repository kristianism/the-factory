//SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

contract MockFactory {
    address public feeCollector;

    modifier onlyCollector() {
        require(msg.sender == feeCollector, "Not authorized");
        _;
    }

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    function pendingFees() public view returns (uint256) {
        return address(this).balance;
    }

    function collectFees() external onlyCollector {
        uint256 fees = pendingFees();
        require(fees > 0, "No fees to collect");

        // Simulate fee collection logic
        payable(feeCollector).transfer(fees);
    }
}
