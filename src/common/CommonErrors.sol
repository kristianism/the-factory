// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

abstract contract CommonErrors {
    /**
     * COMMON ERRORS
     */
    /// @notice Thrown when the address is zero.
    error ZeroAddress();
    /// @notice Thrown when the amount is zero.
    error ZeroAmount();
    /// @notice Thrown when the payable amount is invalid
    error InvalidFee();
    /// @notice Thrown when the address is invalid
    error InvalidAddress();
    /// @notice Error thrown when an invalid implementation address is provided.
    error InvalidImplementationAddress();
    /// @notice Thrown when the caller is not the collector.
    error InvalidCollector();
    /// @notice Thrown when the input is invalid
    error InputCannotBeNull();
    /// @notice Thrown when the contract has insufficient funds.
    error InsufficientFunds();
}
