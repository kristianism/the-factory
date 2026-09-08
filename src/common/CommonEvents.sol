// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

abstract contract CommonEvents {
    /**
     * COMMON EVENTS
     */
    /// @notice Emitted when a new fee collector is set.
    event FeeCollectorUpdated(address indexed feeCollector);
    /// @notice Emitted when a new creation fee is set.
    event CreationFeeUpdated(uint256 creationFee);
    /// @notice Emitted when fees are collected.
    event FeesCollected(address indexed feeCollector, uint256 amount);
}
