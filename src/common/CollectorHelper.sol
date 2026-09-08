// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

/**
 * @title Collector Helper
 * @notice Extension contract for fee collection related functions
 */
abstract contract CollectorHelper is CommonErrors, CommonEvents {
    using SafeERC20 for IERC20;

    /// @notice The address that collects the fees.
    address public feeCollector;

    /// @notice Modifier to check if the caller is the collector.
    modifier onlyCollector() {
        require(msg.sender == feeCollector, InvalidCollector());
        _;
    }

    /// @notice Constructor to initialize the contract with an owner and fee collector.
    /// @param _feeCollector The address of the fee collector.
    constructor(address _feeCollector) {
        if (_feeCollector == address(0)) revert ZeroAddress();

        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice This function allows the owner to collect the contract balance.
    /// @dev Factories should expose a privileged wrapper for this function.
    function _collectFees() internal {
        if (feeCollector == address(0)) revert ZeroAddress();
        if (address(this).balance == 0) revert ZeroAmount();

        uint256 balance = address(this).balance;
        (bool success,) = feeCollector.call{value: balance}("");
        require(success, "Failed to send Ether");

        emit FeesCollected(feeCollector, balance);
    }

    /// @notice This function allows the owner to collect foreign tokens sent to the contract.
    /// @dev Factories should expose a privileged wrapper for this function.
    /// @param token The address of the token to collect.
    function _collectTokens(address token) internal {
        if (token == address(0)) revert ZeroAddress();
        if (IERC20(token).balanceOf(address(this)) == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(feeCollector, balance);
    }

    /// @notice This function allows the owner to update the fee collector address.
    /// @dev Factories should expose a privileged wrapper for this function.
    /// @param newFeeCollector The new address for the fee collector.
    function _setFeeCollector(address newFeeCollector) internal {
        if (newFeeCollector == address(0)) revert ZeroAddress();

        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    /// @notice This function allows the owner to check the pending fees in the contract.
    /// @return The amount of pending fees in the contract.
    function pendingFees() external view returns (uint256) {
        return address(this).balance;
    }
}
