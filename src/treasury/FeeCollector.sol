// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";
import {IFactory} from "@treasury/interface/IFactory.sol";

/**
 * @title Fee Collector
 * @notice This contract is responsible for collecting fees from the whole protocol.
 */
contract FeeCollector is
    Initializable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    CommonErrors,
    CommonEvents
{
    using SafeERC20 for IERC20;

    /// @notice Error thrown when empty factory list provided
    error EmptyFactoryList();
    /// @notice Error thrown when insufficient fees to collect
    error InsufficientFees();

    /// @notice Emitted when fees are collected from factories
    event FeesCollected(address[] factories, uint256 totalAmount);
    /// @notice Emitted when treasury is updated
    event TreasuryUpdated(address indexed newTreasury);
    /// @notice Emitted when collection threshold is updated
    event CollectionThresholdUpdated(uint256 newThreshold);

    /// @notice Structure to hold factory fee information
    struct FactoryFeeInfo {
        address factory;
        uint256 pendingFees;
        bool success;
    }

    /// @notice Treasury address where collected fees are sent
    address public treasury;

    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize the contract.
    /// @param _initialOwner The address of the initial owner of the contract.
    /// @param _treasury The treasury address where fees are sent.
    function initialize(address _initialOwner, address _treasury) external initializer {
        if (_initialOwner == address(0) || _treasury == address(0)) revert ZeroAddress();

        __Ownable2Step_init();
        __Ownable_init(_initialOwner);

        treasury = _treasury;
    }

    /// @notice Function to receive ETH from factory contracts
    receive() external payable {}

    /// @notice Collect fees from specified factories
    /// @param factories Array of factory addresses to collect from
    /// @dev Caller is responsible for providing valid factory addresses
    function collectFees(address[] calldata factories) external onlyOwner nonReentrant {
        if (factories.length == 0) revert EmptyFactoryList();

        uint256 initialBalance = address(this).balance;

        // Collect from all provided factories
        for (uint256 i = 0; i < factories.length; i++) {
            try IFactory(factories[i]).collectFees() {
            // Success - continue
            }
                catch {
                // Skip failed collections and continue
            }
        }

        uint256 collectedAmount = address(this).balance - initialBalance;

        if (collectedAmount > 0) {
            // Send to treasury
            (bool success,) = treasury.call{value: collectedAmount}("");
            require(success, "Treasury transfer failed");

            emit FeesCollected(factories, collectedAmount);
        }
    }

    /// @notice Get total pending fees for specific factories
    /// @param factories Array of factory addresses to check
    /// @return total Total pending fees across provided factories
    function getTotalPendingFees(address[] calldata factories) external view returns (uint256 total) {
        for (uint256 i = 0; i < factories.length; i++) {
            try IFactory(factories[i]).pendingFees() returns (uint256 pending) {
                total += pending;
            } catch {
                // Skip factories that don't support pendingFees()
            }
        }
    }

    /// @notice Get individual pending fees for each factory
    /// @param factories Array of factory addresses to check
    /// @return factoryFees Array of FactoryFeeInfo structs with individual balances
    function getFactoryFees(address[] calldata factories) external view returns (FactoryFeeInfo[] memory factoryFees) {
        factoryFees = new FactoryFeeInfo[](factories.length);

        for (uint256 i = 0; i < factories.length; i++) {
            factoryFees[i].factory = factories[i];

            try IFactory(factories[i]).pendingFees() returns (uint256 pending) {
                factoryFees[i].pendingFees = pending;
                factoryFees[i].success = true;
            } catch {
                factoryFees[i].pendingFees = 0;
                factoryFees[i].success = false;
            }
        }
    }

    /// @notice Emergency function to collect any ETH
    function collectEth() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = treasury.call{value: balance}("");
            require(success, "Failed to send Ether to treasury");
        }
    }

    /// @notice Emergency function to collect any ERC20 tokens
    /// @param token Address of the token to collect
    function collectTokens(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(treasury, balance);
        }
    }

    /// @notice Set new treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner nonReentrant {
        if (_treasury == address(0)) revert ZeroAddress();

        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @notice Function to authorize the upgrade of the contract.
    /// @dev This function is called by the UUPS proxy to authorize upgrades.
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        if (newImplementation == address(0)) revert InvalidImplementationAddress();
    }
}
