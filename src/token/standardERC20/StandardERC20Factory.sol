// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@standardERC20/StandardERC20.sol";
import "@common/CollectorHelper.sol";
import "@common/Referral.sol";

/**
 * @title Standard ERC20 Factory
 * @notice This contract clones a standard ERC20 token implementation.
 * @dev Proxy implementation are Clones. Implementation is immutable and not upgradeable.
 */
contract StandardERC20Factory is 
    Ownable,
    Pausable,
    ReentrancyGuard,
    CollectorHelper,
    Referral
{
    using SafeERC20 for IERC20;

    /// @notice Event emitted when a token is created on the platform.
    event TokenCreated(address indexed token, address indexed owner);

    /// @notice Information of each token
    struct TokenInfo {
        address tokenAddress;
        address creator;
        string name;
        string symbol;
        uint256 tokenId;
    }

    /// @notice The address of the token implementation contract
    address public immutable tokenImplementation;
    /// @notice The fee to be paid when creating a token.
    uint256 public creationFee;
    /// @notice The count of tokens created by the platform.
    uint256 public tokenCounter;

    /// @notice Mapping for the token ID and token address.
    mapping(uint256 tokenId => address tokenAddress) internal IdToAddress;
    /// @notice Mapping from creator address to their token addresses.
    mapping(address creator => address[] tokens) internal creatorToTokens;
    /// @notice Mapping from token address to its registry information.
    mapping(address token => TokenInfo info) internal tokenInfo;

    /// @notice Constructor arguments for the token factory.
    /// @param _tokenImplementation This is the address of the token to be cloned.
    /// @param _initialOwner The initial owner of the contract.
    /// @param _feeCollector The address that collects the fees.
    /// @param _creationFee The amount to collect for every contract creation.
    constructor(
        address _tokenImplementation,
        address _initialOwner,
        address _feeCollector,
        uint256 _creationFee
    ) Ownable(_initialOwner) CollectorHelper(_feeCollector) {
        if (
            _initialOwner == address(0) ||
            _tokenImplementation == address(0) ||
            _feeCollector == address(0)
        ) revert ZeroAddress();

        tokenImplementation = _tokenImplementation;
        creationFee = _creationFee;

        _pause();
    }

    /// @notice This function allows the contract to receive ETH. 
    receive() external payable {}

    /// @notice This function is called to create a new token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param initialSupply The initial supply of the token
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _referrer
    ) external payable whenNotPaused nonReentrant returns (address token) {
        if(
            bytes(name).length == 0 || 
            bytes(symbol).length == 0
        ) revert InputCannotBeNull();
        if(msg.value < creationFee) revert InvalidFee();

        tokenCounter = tokenCounter + 1;

        token = Clones.clone(tokenImplementation);

        StandardERC20(token).initialize(
            name, 
            symbol, 
            initialSupply, 
            msg.sender
        );

        IdToAddress[tokenCounter] = token;
        creatorToTokens[msg.sender].push(token);

        tokenInfo[token] = TokenInfo({
            tokenAddress: token,
            creator: msg.sender,
            name: name,
            symbol: symbol,
            tokenId: tokenCounter
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

        emit TokenCreated(token, msg.sender);
    }

    /// @notice This function allows the fee collector to collect the fees.
    function collectFees() external onlyCollector {
        _collectFees();
    }

    /// @notice This function allows the fee collector to collect foreign tokens sent to the contract.
    /// @param token The address of the token to collect.
    function collectTokens(address token) external onlyOwner {
        _collectTokens(token);
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

    /// @notice Get the total number of Tokens created.
    function getTotalTokens() external view returns (uint256) {
        return tokenCounter;
    }

    /// @notice Get the Token address by its ID.
    /// @param tokenId The ID of the token to retrieve.
    function getTokenById(uint256 tokenId) external view returns (address) {
        return IdToAddress[tokenId];
    }

    /// @notice Get all Tokens created by a specific creator.
    /// @param creator The address of the creator to retrieve tokens for.
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        return creatorToTokens[creator];
    }

    /// @notice Get the Token information by its address.
    /// @param token The address of the token to retrieve information for.
    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        return tokenInfo[token];
    }

    /// @notice Validates if the Token address is valid.
    /// @param token The address of the token to validate.
    function isValidToken(address token) external view returns (bool) {
        return tokenInfo[token].tokenAddress == token;
    }
}