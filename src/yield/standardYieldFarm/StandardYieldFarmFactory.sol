//SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StandardYieldFarm} from "@standardYield/StandardYieldFarm.sol";
import {CollectorHelper} from "@common/CollectorHelper.sol";

/**
 * @title Standard Yield Farm Factory
 * @notice This is a factory for creating Standard Yield Farm contracts.
 * @dev Proxy implementation are Clones. Implementation is immutable and not upgradeable.
 */
contract StandardYieldFarmFactory is 
    Ownable,
    Pausable, 
    ReentrancyGuard,
    CollectorHelper
{
    using SafeERC20 for IERC20;

    /// @notice Thrown when the start timestamp is not in the future
    error InvalidTimestamp();

    /// @notice Emitted when a new yield farm is created.
    event YieldFarmCreated(
        address indexed yieldFarm,
        address indexed creator,
        address feeAddress,
        uint256 rewardPerSec,
        uint256 startTimestamp,
        uint256 yieldFarmId
    );

    /// @notice Information of each yield farm.
    struct YieldFarmInfo {
        address yieldFarmAddress;
        address creator;
        address feeAddress;
        uint256 rewardPerSecond;
        uint256 startTimestamp;
        uint256 yieldFarmId;
    }

    /// @notice The address of the standard yield farm implementation contract.
    address public immutable yieldFarmImplementation;
    /// @notice The address of the standard token implementation contract.
    address public immutable tokenImplementation;
    /// @notice The fee to create a new yield farm.
    uint256 public creationFee;
    /// @notice The number of yield farms created.
    uint256 internal yieldFarmCounter;

    /// @notice Mapping from yield farm ID to yield farm address.
    mapping(uint256 yieldFarmId => address yieldFarmAddress) internal IdToAddress;
    /// @notice Mapping from creator address to their yield farm addresses.
    mapping(address creator => address[] yieldFarm) internal creatorToYieldFarms;
    /// @notice Mapping from yield farm address to its registry information.
    mapping(address yieldFarm => YieldFarmInfo info) internal yieldFarmInfo;

    /**
     * @notice Constructor arguments for the yield farm factory.
     * @param _yieldFarmImplementation This is the address of the yield farm to be cloned.
     * @param _initialOwner The initial owner of the factory.
     * @param _feeCollector The address that will collect the creation fees.
     * @param _creationFee The amount to collect for every contract creation.
     */
    constructor(
        address _yieldFarmImplementation,
        address _initialOwner,
        address _feeCollector,
        uint256 _creationFee
    ) Ownable(_initialOwner) CollectorHelper(_feeCollector) {
        if(_yieldFarmImplementation == address(0)) revert ZeroAddress();

        yieldFarmImplementation = _yieldFarmImplementation;
        creationFee = _creationFee;

        _pause();
    }

    /// @notice This function allows the contract to receive ETH.
    receive() external payable {}

    /**
     * @notice This function is called to create a new yield farm contract.
     * @param _rewardToken The token that will be used as a reward in the yield farm.
     * @param _feeAddress The address that will receive the deposit fees.
     * @param _rewardPerSecond The amount of reward tokens distributed per second.
     * @param _startTimestamp The timestamp when the yield farm starts.
    */
    function createYieldFarm(
        IERC20 _rewardToken,
        address _feeAddress,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp
    ) external payable whenNotPaused nonReentrant returns (address payable yieldFarm) {
        if(_startTimestamp < block.timestamp) revert InvalidTimestamp();
        if(msg.value < creationFee) revert InvalidFee();

        yieldFarmCounter = yieldFarmCounter + 1;

        yieldFarm = payable(Clones.clone(yieldFarmImplementation));

        StandardYieldFarm(yieldFarm).initialize(
            _rewardToken,
            msg.sender,
            _feeAddress,
            _rewardPerSecond,
            _startTimestamp
        );

        IdToAddress[yieldFarmCounter] = yieldFarm;
        creatorToYieldFarms[msg.sender].push(yieldFarm);

        yieldFarmInfo[yieldFarm] = YieldFarmInfo({
            yieldFarmAddress: yieldFarm,
            creator: msg.sender,
            feeAddress: _feeAddress,
            rewardPerSecond: _rewardPerSecond,
            startTimestamp: _startTimestamp,
            yieldFarmId: yieldFarmCounter
        });

        // Refund excess ETH if any.
        uint256 excessNative = msg.value - creationFee;
        if (excessNative > 0) {
            (bool excessSuccess, ) = msg.sender.call{value: excessNative}("");
            require(excessSuccess, "Failed to refund excess ETH");
        }

        emit YieldFarmCreated(
            yieldFarm,
            msg.sender,
            _feeAddress,
            _rewardPerSecond, 
            _startTimestamp,
            yieldFarmCounter
        );
    }

    /// @notice This function sets the creation fee.
    /// @param _creationFee The amount to set as the creation fee.
    function setCreationFee(uint256 _creationFee) external onlyOwner {       
        creationFee = _creationFee;
        emit CreationFeeUpdated(_creationFee);
    }

    /// @notice This function allows the owner to pause the contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice This function allows the owner to unpause the contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Get the total number of yield farms created.
    function getTotalLockers() external view returns (uint256) {
        return yieldFarmCounter;
    }

    /// @notice  Get the yield farm address by its ID.
    /// @param yieldFarmId The ID of the yield farm to retrieve.
    function getYieldFarmById(uint256 yieldFarmId) external view returns (address) {
        return IdToAddress[yieldFarmId];
    }

    /// @notice Get all yield farms created by a specific creator.
    /// @param creator The address of the creator to retrieve yield farms for.
    function getYieldFarmsByCreator(address creator) external view returns (address[] memory) {
        return creatorToYieldFarms[creator];
    }

    /// @notice Get the yield farm information by its address.
    /// @param yieldFarm The address of the yield farm to retrieve information for.
    function getYieldFarmInfo(address yieldFarm) external view returns (YieldFarmInfo memory) {
        return yieldFarmInfo[yieldFarm];
    }

    /// @notice Validates if the yield farm address is valid.
    /// @param yieldFarm The address of the yield farm to validate.
    function isValidYieldFarm(address yieldFarm) external view returns (bool) {
        return yieldFarmInfo[yieldFarm].yieldFarmAddress == yieldFarm;
    }
}