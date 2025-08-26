// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@taxToken/TaxToken.sol";
import "@common/CollectorHelper.sol";
import "@common/Referral.sol";

/**
 * @title Tax Token Factory
 * @notice This is a factory for creating TaxToken contracts.
 * @dev Proxy implementation are Clones. Implementation is immutable and not upgradeable.
 */
contract TaxTokenFactory is 
    Ownable,
    Pausable,
    ReentrancyGuard,
    CollectorHelper,
    Referral
{
    using SafeERC20 for IERC20;

    /// @notice Event emitted when a tax token is created on the platform.
    event TaxTokenCreated(address indexed taxToken, address indexed owner);

    /// @notice Information of each Tax Token
    struct TaxTokenInfo {
        address tokenAddress;
        address creator;
        string name;
        string symbol;
        uint256 tokenId;
    }

    /// @notice The address of the token implementation contract.
    address public immutable taxTokenImplementation;
    /// @notice The fee to create a new token.
    uint256 public creationFee;
    /// @notice The number of tokens created.
    uint256 public tokenCounter;

    /// @notice Mapping from token ID to token address.
    mapping(uint256 tokenId => address tokenAddress) internal IdToAddress;
    /// @notice Mapping from creator address to their tax token addresses.
    mapping(address creator => address[] taxTokens) internal creatorToTaxToken;
    /// @notice Mapping from Tax Token address to its registry information.
    mapping(address taxToken => TaxTokenInfo info) internal taxTokenInfo;

    /// @notice Constructor arguments for the token factory.
    /// @param _taxTokenImplementation This is the address of the token to be cloned.
    /// @param _initialOwner The initial owner of the contract.
    /// @param _feeCollector The address that collects the fees.
    /// @param _creationFee The amount to collect for every contract creation.
    constructor(
        address _taxTokenImplementation,
        address _initialOwner,
        address _feeCollector,
        uint256 _creationFee
    ) Ownable(_initialOwner) CollectorHelper(_feeCollector) {
        if (
            _initialOwner == address(0) || 
            _taxTokenImplementation == address(0) ||
            _feeCollector == address(0)
        ) revert ZeroAddress();

        taxTokenImplementation = _taxTokenImplementation;
        creationFee = _creationFee;

        _pause();
    }

    /// @notice This function allows the contract to receive ETH.
    receive() external payable {}

    /// @notice This function is called to create a new token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param initialSupply The initial supply of the token
    /// @param transferTaxRate The transfer tax rate of the token
    /// @param taxBeneficiary The address of the tax beneficiary
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 transferTaxRate,
        address taxBeneficiary,
        address _referrer
    ) external payable whenNotPaused nonReentrant returns (address taxToken) {
        if(bytes(name).length == 0 || bytes(symbol).length == 0) revert InputCannotBeNull();
        if(taxBeneficiary == address(0)) revert ZeroAddress();
        if(msg.value < creationFee) revert InvalidFee();

        tokenCounter = tokenCounter + 1;

        taxToken = Clones.clone(taxTokenImplementation);

        TaxToken(taxToken).initialize(
            name,
            symbol,
            initialSupply,
            transferTaxRate,
            taxBeneficiary,
            msg.sender
        );

        IdToAddress[tokenCounter] = taxToken;
        creatorToTaxToken[msg.sender].push(taxToken);

        taxTokenInfo[taxToken] = TaxTokenInfo({
            tokenAddress: taxToken,
            creator: msg.sender,
            name: name,
            symbol: symbol,
            tokenId: tokenCounter
        });

        uint256 excessEth = msg.value - creationFee;

        // Refund excess ETH if any.
        if (excessEth > 0) {
            (bool success, ) = msg.sender.call{value: excessEth}("");
            require(success, "Failed to refund excess ETH");
        }

        // Distribute referral if applicable
        if(_referrer != address(0) && _referrer != msg.sender && referralRate > 0 && creationFee > 0) {
            _distributeReferral(_referrer, creationFee);
        }

        emit TaxTokenCreated(taxToken, msg.sender);
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

    /// @notice Get the total number of Tax Tokens created.
    function getTotalTaxTokens() external view returns (uint256) {
        return tokenCounter;
    }

    /// @notice Get the Tax Token address by its ID.
    /// @param tokenId The ID of the token to retrieve.
    function getTaxTokenById(uint256 tokenId) external view returns (address) {
        return IdToAddress[tokenId];
    }

    /// @notice Get all Tax Tokens created by a specific creator.
    /// @param creator The address of the creator to retrieve tokens for.
    function getTaxTokensByCreator(address creator) external view returns (address[] memory) {
        return creatorToTaxToken[creator];
    }

    /// @notice Get the Tax Token information by its address.
    /// @param taxToken The address of the tax token to retrieve information for.
    function getTaxTokenInfo(address taxToken) external view returns (TaxTokenInfo memory) {
        return taxTokenInfo[taxToken];
    }

    /// @notice Validates if the Tax Token address is valid.
    /// @param taxToken The address of the tax token to validate.
    function isValidTaxToken(address taxToken) external view returns (bool) {
        return taxTokenInfo[taxToken].tokenAddress == taxToken;
    }
}