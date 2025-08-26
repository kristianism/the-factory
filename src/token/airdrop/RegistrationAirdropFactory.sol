// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {RegistrationAirdrop} from "@airdrop/RegistrationAirdrop.sol";
import {CollectorHelper} from "@common/CollectorHelper.sol";
import {Referral} from "@common/Referral.sol";

/**
 * @title Registration-Based Airdrop Factory
 * @notice This contract deploys a registration-based airdrop contract.
 * @dev Proxy implementation are Clones. Implementation is immutable and not upgradeable.
 */
contract RegistrationAirdropFactory is 
    Ownable,
    Pausable,
    ReentrancyGuard,
    CollectorHelper,
    Referral
{

    /// @notice Information of each airdrop
    struct AirdropInfo {
        address airdropAddress;
        address creator;
        address token;
        uint256 airdropId;
    }

    /// @notice Event emitted when a airdrop is created on the platform.
    event AirdropCreated(address indexed airdrop, address indexed owner);

    /// @notice The address of the airdrop implementation contract
    address public immutable airdropImplementation;
    /// @notice The fee to be paid when creating a airdrop.
    uint256 public creationFee;
    /// @notice The count of airdrops created by the platform.
    uint256 public airdropCounter;

    /// @notice Mapping for the airdrop ID and airdrop address.
    mapping(uint256 airdropId => address airdropAddress) internal IdToAddress;
    /// @notice Mapping from creator address to their airdrop addresses.
    mapping(address creator => address[] airdrops) internal creatorToAirdrop;
    /// @notice Mapping from airdrop address to its registry information.
    mapping(address airdrop => AirdropInfo info) internal airdropInfo;

    /// @notice Constructor arguments for the airdrop factory.
    /// @param _airdropImplementation This is the address of the airdrop to be cloned.
    /// @param _initialOwner The initial owner of the contract.
    /// @param _feeCollector The address that collects the fees.
    /// @param _creationFee The amount to collect for every contract creation.
    constructor(
        address _airdropImplementation,
        address _initialOwner,
        address _feeCollector,
        uint256 _creationFee
    ) Ownable(_initialOwner) CollectorHelper(_feeCollector) {
        if (
            _initialOwner == address(0) ||
            _airdropImplementation == address(0) || 
            _feeCollector == address(0)
        ) revert ZeroAddress();

        airdropImplementation = _airdropImplementation;
        creationFee = _creationFee;

        _pause();
    }

    /// @notice This function allows the contract to receive ETH. 
    receive() external payable {}

    /// @notice This function is called to create a new airdrop
    /// @param _token The ERC20 token address to be airdropped
    /// @param _baseAmount The base amount allocated per user
    /// @param _referrer The address of the referrer for the creation fee
    function createAirdrop(
        address _token,
        uint256 _baseAmount,
        address _referrer
    ) external payable whenNotPaused nonReentrant returns (address airdrop) {
        if(_token == address(0)) revert ZeroAddress();
        if(_baseAmount == 0) revert ZeroAmount();
        if(msg.value < creationFee) revert InvalidFee();

        airdropCounter = airdropCounter + 1;

        airdrop = Clones.clone(airdropImplementation);

        RegistrationAirdrop(airdrop).initialize(
            _token, 
            _baseAmount, 
            msg.sender
        );

        IdToAddress[airdropCounter] = airdrop;
        creatorToAirdrop[msg.sender].push(airdrop);

        airdropInfo[airdrop] = AirdropInfo({
            airdropAddress: airdrop,
            creator: msg.sender,
            token: _token,
            airdropId: airdropCounter
        });

        uint256 excessEth = msg.value - creationFee;

        // Refund excess ETH if any.
        if(excessEth > 0) {
            (bool success, ) = msg.sender.call{value: excessEth}("");
            require(success, "Failed to refund excess ETH");
        }

        // Distribute referral if applicable
        if(_referrer != address(0) && _referrer != msg.sender && referralRate > 0 && creationFee > 0) {
            _distributeReferral(_referrer, creationFee);
        }

        emit AirdropCreated(airdrop, msg.sender);
    }

    /// @notice This function allows the fee collector to collect the fees.
    function collectFees() external onlyCollector {
        _collectFees();
    }

    /// @notice This function allows the fee collector to collect foreign airdrops sent to the contract.
    /// @param airdrop The address of the airdrop to collect.
    function collectTokens(address airdrop) external onlyOwner {
        _collectTokens(airdrop);
    }

    /// @notice This function sets the fee collector address.
    /// @param newFeeCollector The new address for the fee collector.
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        _setFeeCollector(newFeeCollector);
    }

    /// @notice This function sets the creation fee.
    function setCreationFee(uint256 _creationFee) external onlyOwner {
        creationFee = _creationFee;
        emit CreationFeeUpdated(_creationFee);
    }

    /// @notice This function sets the referral rate.
    /// @param _referralRate The new referral rate in basis points (0..10_000).
    function setReferralRate(uint256 _referralRate) external onlyOwner {
        _setReferralRate(_referralRate);
    }

    /// @notice This function allows the owner to pause the contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice This function allows the owner to unpause the contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Get the total number of airdrops created.
    function getTotalAirdrops() external view returns (uint256) {
        return airdropCounter;
    }

    /// @notice Get the airdrop address by its ID.
    /// @param airdropId The ID of the airdrop to retrieve.
    function getAirdropById(uint256 airdropId) external view returns (address) {
        return IdToAddress[airdropId];
    }

    /// @notice Get all airdrops created by a specific creator.
    /// @param creator The address of the creator to retrieve airdrops for.
    function getAirdropsByCreator(address creator) external view returns (address[] memory) {
        return creatorToAirdrop[creator];
    }

    /// @notice Get the airdrop information by its address.
    /// @param airdrop The address of the airdrop to retrieve information for.
    function getAirdropInfo(address airdrop) external view returns (AirdropInfo memory) {
        return airdropInfo[airdrop];
    }

    /// @notice Validates if the airdrop address is valid.
    /// @param airdrop The address of the airdrop to validate.
    function isValidAirdrop(address airdrop) external view returns (bool) {
        return airdropInfo[airdrop].airdropAddress == airdrop;
    }
}