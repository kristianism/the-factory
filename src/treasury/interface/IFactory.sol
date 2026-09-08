//SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.36;

/**
 * @title Factory Interface
 * @notice Universal interface for the factories
 * @dev The interface contains function for fees
 */
interface IFactory {
    function collectFees() external;
    function pendingFees() external view returns (uint256);
}
