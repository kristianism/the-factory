// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20BurnableUpgradeable} from 
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

/**
 * @title Standard ERC20 Token
 * @notice This contract implements a standard ERC20 token with burnable functionality.
 */
contract StandardERC20 is 
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    CommonErrors,
    CommonEvents
{
    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice This function is called by the TokenFactory contract to initialize the token
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param initialSupply The initial supply of the token
    /// @param developer The address of the developer 
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 initialSupply,
        address developer
    ) external initializer {
        __ERC20Burnable_init();
        __ERC20_init(_name, _symbol);
        __Ownable_init(developer);
        _mint(developer, initialSupply);
    }

    /// @notice This function allows the owner to mint new tokens
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}