// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.36;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

/**
 * @title Tax Token
 * @notice This contract implements an ERC20 token with a transfer tax mechanism.
 */
contract TaxToken is Initializable, ERC20Upgradeable, Ownable2StepUpgradeable, CommonErrors, CommonEvents {
    /// @notice Thrown when the tax rate exceeds the maximum tax rate
    error TaxRateExceedsMax();

    /// @notice Event emitted when the transfer tax rate is updated.
    event TransferTaxRateUpdated(address indexed owner, uint256 newRate);
    /// @notice Event emitted when the tax beneficiary address is updated.
    event TaxBeneficiaryUpdated(address indexed owner, address indexed taxBeneficiary);
    /// @notice Event emitted when a no tax sender address is set.
    event SetNoTaxSenderAddr(address indexed owner, address indexed noTaxSenderAddr, bool _value);
    /// @notice Event emitted when a no tax recipient address is set.
    event SetNoTaxRecipientAddr(address indexed owner, address indexed noTaxRecipientAddr, bool _value);

    /// @notice Scaling factor for decimal precision.
    uint256 public constant SCALING_FACTOR = 10_000;
    /// @notice The tax limit by default (20%)
    uint256 public constant MAXIMUM_TAX = 2_000;
    /// @notice Transfer tax rate in basis points. (default = 5%)
    uint256 public transferTaxRate;
    /// @notice Transfer tax beneficiary address.
    address public taxBeneficiary;

    /// @notice Recipient addresses that are to be excluded from tax.
    mapping(address => bool) public noTaxRecipient;
    /// @notice Sender addresses that are to be excluded from tax.
    mapping(address => bool) public noTaxSender;

    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialization arguments for the TaxToken contract.
    /// @param _name Full name of the token.
    /// @param _symbol Short name of the token.
    /// @param _initialSupply Number of tokens to be minted. Expressed in wei.
    /// @param _transferTaxRate Transfer tax rate to be imposed. Expressed in basis points (ex. 1_000 = 10%).
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _transferTaxRate,
        address _taxBeneficiary,
        address _owner
    ) external initializer {
        if (_transferTaxRate > MAXIMUM_TAX) revert TaxRateExceedsMax();
        if (_taxBeneficiary == address(0)) revert ZeroAddress();

        __ERC20_init(_name, _symbol);
        __Ownable2Step_init();
        __Ownable_init(_owner);

        transferTaxRate = _transferTaxRate;
        taxBeneficiary = _taxBeneficiary;

        noTaxRecipient[_owner] = true;
        noTaxSender[_owner] = true;

        _mint(_owner, _initialSupply);

        emit TransferTaxRateUpdated(msg.sender, transferTaxRate);
        emit TaxBeneficiaryUpdated(msg.sender, taxBeneficiary);
        emit SetNoTaxSenderAddr(msg.sender, _owner, true);
        emit SetNoTaxRecipientAddr(msg.sender, _owner, true);
    }

    /// @notice External privileged function to create or mint an X amount of tokens to a specified address.
    function mint(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        _mint(_to, _amount);
    }

    /// @notice External function to burn or destroy an X amount of tokens.
    function burn(uint256 _amount) external {
        if (_amount == 0) revert ZeroAmount();

        _burn(msg.sender, _amount);
    }

    /// @notice Overrides transfer function to meet tokenomics of tax token
    function _update(address from, address to, uint256 value) internal virtual override {
        if (noTaxRecipient[to] || noTaxSender[from] || from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        uint256 taxAmount = Math.mulDiv(value, transferTaxRate, SCALING_FACTOR, Math.Rounding.Ceil);
        if (taxAmount > 0) super._update(from, taxBeneficiary, taxAmount);
        super._update(from, to, value - taxAmount);
    }

    /// @notice External privileged function to update the transfer tax rate up to the maximum tax rate set.
    function updateTransferTaxRate(uint256 _transferTaxRate) external onlyOwner {
        if (_transferTaxRate > MAXIMUM_TAX) revert TaxRateExceedsMax();

        transferTaxRate = _transferTaxRate;

        emit TransferTaxRateUpdated(msg.sender, _transferTaxRate);
    }

    /// @notice External privileged function to update the tax beneficiary address.
    function updateTaxBeneficiary(address _taxBeneficiary) external onlyOwner {
        if (_taxBeneficiary == address(0)) revert ZeroAddress();

        address previousBeneficiary = taxBeneficiary;
        noTaxRecipient[previousBeneficiary] = false;
        noTaxSender[previousBeneficiary] = false;

        taxBeneficiary = _taxBeneficiary;

        noTaxSender[_taxBeneficiary] = true;
        noTaxRecipient[_taxBeneficiary] = true;

        // Emit events for the previous tax beneficiary
        emit SetNoTaxRecipientAddr(msg.sender, previousBeneficiary, false);
        emit SetNoTaxSenderAddr(msg.sender, previousBeneficiary, false);

        // Emit events for the new tax beneficiary
        emit SetNoTaxSenderAddr(msg.sender, _taxBeneficiary, true);
        emit SetNoTaxRecipientAddr(msg.sender, _taxBeneficiary, true);
        emit TaxBeneficiaryUpdated(msg.sender, _taxBeneficiary);
    }

    /// @notice External privileged function to update the no tax mapping for senders.
    function setNoTaxSenderAddr(address _noTaxSenderAddr, bool _value) external onlyOwner {
        if (_noTaxSenderAddr == address(0)) revert ZeroAddress();
        noTaxSender[_noTaxSenderAddr] = _value;

        emit SetNoTaxSenderAddr(msg.sender, _noTaxSenderAddr, _value);
    }

    /// @notice External privileged function to update the no tax mapping for recipients.
    function setNoTaxRecipientAddr(address _noTaxRecipientAddr, bool _value) external onlyOwner {
        if (_noTaxRecipientAddr == address(0)) revert ZeroAddress();
        noTaxRecipient[_noTaxRecipientAddr] = _value;

        emit SetNoTaxRecipientAddr(msg.sender, _noTaxRecipientAddr, _value);
    }
}
