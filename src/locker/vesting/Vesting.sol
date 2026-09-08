// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.36;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VestingWalletUpgradeable} from "@openzeppelin/contracts-upgradeable/finance/VestingWalletUpgradeable.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

/**
 * @title Vesting
 * @notice This contract allows for the vesting of native or ERC20 tokens to a beneficiary over a specified duration.
 */
contract Vesting is Initializable, ReentrancyGuard, VestingWalletUpgradeable, CommonErrors, CommonEvents {
    /// @notice Thrown when tokens are not vested.
    error NotVested();
    /// @notice Thrown when the start timestamp is not in the future
    error InvalidTimestamp();

    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the given token address and unlock time.
    /// @dev _durationSeconds can be zero to mimic a non-vesting locker.
    /// @param _beneficiary The address of the beneficiary who will receive the vested tokens.
    /// @param _startTimestamp The timestamp when the vesting starts.
    /// @param _durationSeconds The duration in seconds for which the tokens will be vested.
    function initialize(address _beneficiary, uint64 _startTimestamp, uint64 _durationSeconds)
        public
        override
        initializer
    {
        if (_beneficiary == address(0)) revert ZeroAddress();
        if (_startTimestamp < block.timestamp || _startTimestamp == 0) revert InvalidTimestamp();

        __VestingWallet_init(_beneficiary, _startTimestamp, _durationSeconds);
    }

    /// @notice Release the vested ethers to the beneficiary.
    function release() public override nonReentrant {
        if (releasable() == 0) revert NotVested();
        /// @dev Calls the release function from the VestingWalletUpgradeable contract
        super.release();
    }

    /// @notice Release the vest ERC20 tokens to the beneficiary.
    /// @param _token The address of the ERC20 token to be released.
    function release(address _token) public override nonReentrant {
        if (_token == address(0)) revert ZeroAddress();
        if (releasable(_token) == 0) revert NotVested();
        /// @dev Calls the release function from the VestingWalletUpgradeable contract
        super.release(_token);
    }

    /// @notice Renouncing would permanently strand vested assets.
    function renounceOwnership() public override onlyOwner {
        revert("Vesting ownership cannot be renounced");
    }
}
