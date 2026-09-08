// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract Referral {
    /// @notice Referral rate in basis points (0..10_000)
    uint256 internal referralRate;
    /// @notice Maximum referral rate allowed (10_000 = 100%)
    uint256 internal constant MAX_REFERRAL_RATE = 10_000;

    /// @notice Thrown when the referral rate is above the required threshold.
    error InvalidReferralRate(uint256 rate);

    /// @notice Emitted when the referral rate is updated.
    event ReferralRateUpdated(uint256 newRate);
    /// @notice Emitted when a referral payment is made.
    event ReferralPaid(address indexed referrer, uint256 amount, address indexed payer);

    /// @notice Internal setter for referral rate. Factories should expose an onlyOwner wrapper.
    /// @dev _referralRate must be <= 10_000.
    function _setReferralRate(uint256 _referralRate) internal {
        if (_referralRate > MAX_REFERRAL_RATE) revert InvalidReferralRate(_referralRate);
        referralRate = _referralRate;

        emit ReferralRateUpdated(_referralRate);
    }

    /// @notice Distribute referral share of `fee` to `referrer`.
    /// @param referrer The referral address (can be zero address to skip).
    /// @param fee The fee amount (in wei) to split.
    /// @return remainder The amount remaining after referral payout (kept by factory).
    function _distributeReferral(address referrer, uint256 fee) internal returns (uint256 remainder) {
        if (referrer == address(0) || referrer == msg.sender || referralRate == 0 || fee == 0) {
            return fee;
        }

        uint256 referralAmount = Math.mulDiv(fee, referralRate, 10_000);

        if (referralAmount == 0) {
            return fee;
        }

        // Attempt to send referral payment immediately
        (bool sent,) = referrer.call{value: referralAmount, gas: 100_000}("");
        if (sent) {
            emit ReferralPaid(referrer, referralAmount, msg.sender);
            return fee - referralAmount;
        }

        // If sending the referral fails, do not reduce the fee (keep full amount in factory)
        return fee;
    }

    /// @notice External view getter for referral rate.
    function getReferralRate() external view returns (uint256) {
        return referralRate;
    }
}
