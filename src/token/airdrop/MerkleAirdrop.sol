// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Merkle Tree Airdrop
 * @notice This contract allows users to claim ERC20 tokens based on a Merkle proof.
 */
contract MerkleAirdrop is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The ERC20 token being airdropped.
    IERC20 public immutable token;
    /// @notice The merkle root for the airdrop.
    bytes32 public root;
    /// @notice Mapping for address and bool if user has claimed.
    mapping(address => bool) public hasClaimed;

    /// @notice Thrown when the merkle proof is invalid.
    error InvalidProof();
    /// @notice Thrown when the merkle root is invalid.
    error InvalidRoot();
    /// @notice Thrown when the user has already claimed.
    error AlreadyClaimed();
    /// @notice Thrown when the address is zero.
    error ZeroAddress();
    /// @notice Thrown when the value is zero.
    error ZeroAmount();

    /// @notice Emitted when a user claims their tokens.
    event Claimed(address indexed user, uint256 amount);
    /// @notice Emitted when the merkle root is changed.
    event MerkleRootChanged(bytes32 indexed newRoot);
    /// @notice Emitted when the owner withdraws tokens.
    event TokensWithdrawn(address indexed owner, uint256 amount);

    /// @notice Initializes the contract with the merkle root, token address, and owner.
    /// @param _root The merkle root for the airdrop.
    /// @param _token The address of the ERC20 token being airdropped.
    /// @param _owner The address of the contract owner.
    constructor(bytes32 _root, address _token, address _owner) Ownable(_owner) {
        if (_root == bytes32(0)) revert InvalidRoot();
        if (_token == address(0) || _owner == address(0)) revert ZeroAddress();

        if (_token.code.length == 0) revert ZeroAddress();
        root = _root;
        token = IERC20(_token);
    }

    /// @notice Allows a user to claim their tokens if they have a valid merkle proof.
    /// @param proof The merkle proof for the user's claim.
    /// @param amount The amount of tokens the user is claiming.
    function claim(bytes32[] calldata proof, uint256 amount) external nonReentrant {
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (amount == 0) revert ZeroAmount();

        /// @dev Verify the merkle proof.
        _verifyProof(proof, msg.sender, amount);

        /// @dev Mark the user as having claimed.
        hasClaimed[msg.sender] = true;
        /// @dev Transfer the tokens to the user.
        token.safeTransfer(msg.sender, amount);

        /// @dev Emit the Claimed event.
        emit Claimed(msg.sender, amount);
    }

    /// @notice Withdraws tokens from the contract to the owner.
    function withdrawToken(uint256 _amount) external onlyOwner nonReentrant {
        if (_amount == 0) revert ZeroAmount();

        /// @dev Transfer the tokens to the owner.
        token.safeTransfer(owner(), _amount);

        /// @dev Emit the TokensWithdrawn event.
        emit TokensWithdrawn(owner(), _amount);
    }

    /// @notice Changes the merkle root.
    function setMerkleRoot(bytes32 _root) external onlyOwner nonReentrant {
        if (_root == bytes32(0)) revert InvalidRoot();

        /// @dev Change the merkle root.
        root = _root;

        /// @dev Emit the MerkleRootChanged event.
        emit MerkleRootChanged(_root);
    }

    /// @notice Check if an address can claim tokens.
    function canClaim(bytes32[] calldata proof, uint256 amount, address addr) external view returns (bool) {
        if (hasClaimed[addr]) return false;
        if (amount == 0) return false;

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));

        return MerkleProof.verifyCalldata(proof, root, leaf);
    }

    /// @notice Verifies the merkle proof for a given address and amount.
    function _verifyProof(bytes32[] calldata proof, address addr, uint256 amount) internal view {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));

        if (!MerkleProof.verifyCalldata(proof, root, leaf)) revert InvalidProof();
    }
}
