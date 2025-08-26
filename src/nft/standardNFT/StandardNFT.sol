// SPDX-License-Identifier: BSL 1.1
pragma solidity 0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {CommonErrors} from "@common/CommonErrors.sol";
import {CommonEvents} from "@common/CommonEvents.sol";

/**
 * @title Standard NFT
 * @notice This contract is a standard ERC721 implementation
 */
contract StandardNFT is 
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    CommonErrors,
    CommonEvents
{

    /// @notice Error thrown when metadata is locked.
    error MetadataAlreadyLocked();

    /// @notice Event emitted when metadata is locked.
    event MetadataLocked();

    /// @notice The base URI for the NFT metadata.
    string private _baseTokenURI;
    /// @notice The next token ID to be minted.
    uint256 private _nextTokenId;
    /// @notice Lock indicator for metadata changes.
    bool private metadataLocked;

    /// @notice Disables the ability to call the initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the given name, symbol, and base URI.
    /// @param _name The name of the NFT.
    /// @param _symbol The symbol of the NFT.
    /// @param baseURI The base URI for the NFT metadata.
    /// @param _initialOwner The initial owner of the NFT.
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory baseURI,
        address _initialOwner
    )
        public
        initializer
    {
        __ERC721_init(_name, _symbol);
        __Ownable_init(_initialOwner);

        _baseTokenURI = baseURI;
    }

    /// @notice Mints a new NFT to the specified address.
    function safeMint(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /// @notice Updates base URI (only if not locked)
    function setBaseURI(string memory baseURI) external onlyOwner {
        if(metadataLocked) revert MetadataAlreadyLocked();

        _baseTokenURI = baseURI;
    }

    /// @notice Permanently locks metadata (irreversible).
    function lockMetadata() external onlyOwner {
        if(metadataLocked) revert MetadataAlreadyLocked();

        metadataLocked = true;

        emit MetadataLocked();
    }

    /// @notice Returns the total number of tokens minted.
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    /// @notice Checks if metadata is locked.
    /// @return True if metadata is locked, false otherwise.
    function isMetadataLocked() external view returns (bool) {
        return metadataLocked;
    }

    /// @notice Returns the base URI for the NFT metadata.
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

}