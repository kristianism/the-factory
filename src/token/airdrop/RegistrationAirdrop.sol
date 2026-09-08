//SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.36;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

/**
 * @title Registration-Based Airdrop
 * @notice Users register on-chain, then claim tokens based on their registration.
 */
contract RegistrationAirdrop is Ownable2StepUpgradeable, ReentrancyGuard, CommonErrors {
    using SafeERC20 for IERC20;

    /// @notice User registration data
    struct UserData {
        bool isRegistered;
        bool hasClaimed;
        uint256 amount;
        uint256 registrationTime;
    }

    /// @notice Thrown when user registration is already closed.
    error RegistrationClosed();
    /// @notice Thrown when claiming is already closed.
    error ClaimingClosed();
    /// @notice Thrown when user is already registered.
    error AlreadyRegistered();
    /// @notice Thrown when user is not registered.
    error NotRegistered();
    /// @notice Thrown when user has already claimed.
    error AlreadyClaimed();
    /// @notice Thrown when the length of two arrays do not match.
    error LengthMismatch();

    /// @notice Emitted when a user registers.
    event UserRegistered(address indexed user, uint256 amount, uint256 timestamp);
    /// @notice Emitted when a user claims their tokens.
    event Claimed(address indexed user, uint256 amount);
    /// @notice Emitted when registration status changes.
    event RegistrationStatusChanged(bool isOpen);
    /// @notice Emitted when claiming status changes.
    event ClaimingStatusChanged(bool isOpen);
    /// @notice Emitted when base amount changes.
    event BaseAmountChanged(uint256 newAmount);
    /// @notice Emitted when owner withdraws tokens.
    event TokensWithdrawn(address indexed owner, uint256 amount);

    /// @notice The ERC20 token being airdropped.
    IERC20 public token;

    /// @notice Registration phase status
    bool private registrationOpen;
    /// @notice Claim phase status
    bool private claimingOpen;

    /// @notice Fixed amount per user
    uint256 private baseAmount;
    /// @notice Total tokens allocated for airdrop
    uint256 private totalAllocated;
    /// @notice Total registered users
    uint256 private totalRegistered;
    /// @notice Lifetime tokens claimed; outstanding allocation is allocated minus claimed.
    uint256 public totalClaimed;

    /// @notice Array of registered addresses
    address[] private registeredUsers;

    /// @notice Mapping of user address to their data
    mapping(address => UserData) private users;

    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the airdrop contract
    /// @param _token The ERC20 token address to be airdropped
    /// @param _owner The owner address with admin privileges
    /// @param _baseAmount The base amount allocated per user
    function initialize(address _token, uint256 _baseAmount, address _owner) external initializer {
        if (_token == address(0) || _owner == address(0)) revert ZeroAddress();
        if (_baseAmount == 0) revert ZeroAmount();

        __Ownable2Step_init();
        __Ownable_init(_owner);

        if (_token.code.length == 0) revert InvalidAddress();
        token = IERC20(_token);
        baseAmount = _baseAmount;
        registrationOpen = false;
        claimingOpen = false;
    }

    /// @notice Register for the airdrop
    function register() external nonReentrant {
        if (!registrationOpen) revert RegistrationClosed();
        if (users[msg.sender].isRegistered) revert AlreadyRegistered();

        uint256 userAmount = _calculateAllocation();
        if (token.balanceOf(address(this)) < totalAllocated - totalClaimed + userAmount) revert InsufficientFunds();

        users[msg.sender] =
            UserData({isRegistered: true, hasClaimed: false, amount: userAmount, registrationTime: block.timestamp});

        registeredUsers.push(msg.sender);
        totalRegistered++;
        totalAllocated += userAmount;

        emit UserRegistered(msg.sender, userAmount, block.timestamp);
    }

    /// @notice Claim tokens after registration
    /// @dev Make sure to exclude the contract on fee-on-transfer tokens
    function claim() external nonReentrant {
        if (!claimingOpen) revert ClaimingClosed();
        if (!users[msg.sender].isRegistered) revert NotRegistered();
        if (users[msg.sender].hasClaimed) revert AlreadyClaimed();

        uint256 amount = users[msg.sender].amount;
        if (amount == 0) revert ZeroAmount();
        if (token.balanceOf(address(this)) < amount) revert InsufficientFunds();

        users[msg.sender].hasClaimed = true;
        totalClaimed += amount;
        token.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    /// @notice Fixed allocation for a user
    /// @dev Can be extended for more complex logic
    function _calculateAllocation() internal view returns (uint256) {
        return baseAmount;
    }

    /// @notice Batch register multiple users
    function batchRegister(address[] calldata addresses, uint256[] calldata amounts) external onlyOwner nonReentrant {
        if (addresses.length != amounts.length) revert LengthMismatch();

        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            if (!users[addresses[i]].isRegistered) {
                users[addresses[i]] = UserData({
                    isRegistered: true, hasClaimed: false, amount: amounts[i], registrationTime: block.timestamp
                });

                registeredUsers.push(addresses[i]);
                totalRegistered++;
                totalAllocated += amounts[i];

                emit UserRegistered(addresses[i], amounts[i], block.timestamp);
            }
        }
        if (token.balanceOf(address(this)) < totalAllocated - totalClaimed) revert InsufficientFunds();
    }

    /// @notice Toggle registration phase
    /// @param _isOpen True to open registration, false to close
    function setRegistrationStatus(bool _isOpen) external onlyOwner nonReentrant {
        registrationOpen = _isOpen;
        emit RegistrationStatusChanged(_isOpen);
    }

    /// @notice Toggle claiming phase
    /// @param _isOpen True to open claiming, false to close
    function setClaimingStatus(bool _isOpen) external onlyOwner nonReentrant {
        claimingOpen = _isOpen;
        emit ClaimingStatusChanged(_isOpen);
    }

    /// @notice Update base amount for new registrations
    /// @param _baseAmount New base amount
    function setBaseAmount(uint256 _baseAmount) external onlyOwner nonReentrant {
        if (_baseAmount == 0) revert ZeroAmount();
        baseAmount = _baseAmount;
        emit BaseAmountChanged(_baseAmount);
    }

    /// @notice Withdraw tokens from contract
    /// @param _amount Amount to withdraw
    function withdrawToken(uint256 _amount) external onlyOwner nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        uint256 balance = token.balanceOf(address(this));
        uint256 outstanding = totalAllocated - totalClaimed;
        if (balance < outstanding || _amount > balance - outstanding) revert InsufficientFunds();
        token.safeTransfer(owner(), _amount);
        emit TokensWithdrawn(owner(), _amount);
    }

    /// @notice Check if user can claim
    /// @param user The address of the user
    function canClaim(address user) external view returns (bool) {
        return claimingOpen && users[user].isRegistered && !users[user].hasClaimed && users[user].amount > 0
            && token.balanceOf(address(this)) >= users[user].amount;
    }

    /// @notice Get registration status
    function isRegistrationOpen() external view returns (bool) {
        return registrationOpen;
    }

    /// @notice Get claiming status
    function isClaimingOpen() external view returns (bool) {
        return claimingOpen;
    }

    /// @notice Get token address
    function getTokenAddress() external view returns (address) {
        return address(token);
    }

    /// @notice Get base amount per user
    function getBaseAmount() external view returns (uint256) {
        return baseAmount;
    }

    /// @notice Get total allocated tokens for airdrop
    function getTotalAllocated() external view returns (uint256) {
        return totalAllocated;
    }

    /// @notice Get total registered users
    function getTotalRegistered() external view returns (uint256) {
        return totalRegistered;
    }

    /// @notice Get user registration data
    /// @param user The address of the user
    function getUserData(address user) external view returns (UserData memory) {
        return users[user];
    }

    /// @notice Get all registered users
    /// @param offset The starting index
    /// @param limit The maximum number of users to return
    function getRegisteredUsers(uint256 offset, uint256 limit) external view returns (address[] memory) {
        if (offset >= registeredUsers.length) {
            return new address[](0);
        }

        uint256 remaining = registeredUsers.length - offset;
        uint256 end = offset + (limit < remaining ? limit : remaining);
        if (end > registeredUsers.length) {
            end = registeredUsers.length;
        }

        address[] memory result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = registeredUsers[i];
        }

        return result;
    }

    /// @notice Get contract stats
    function getStats()
        external
        view
        returns (
            uint256 _totalRegistered,
            uint256 _totalAllocated,
            uint256 _contractBalance,
            bool _registrationOpen,
            bool _claimingOpen
        )
    {
        return (totalRegistered, totalAllocated, token.balanceOf(address(this)), registrationOpen, claimingOpen);
    }
}
