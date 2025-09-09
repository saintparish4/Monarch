// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseAccount.sol";

/**
 * @title BaseSmartAccount
 * @dev EIP-4337 compatible smart account with advanced features
 * Suppoers gasless transactions, app permissions, and recovery mechanisms
 */

contract BaseSmartAccount is Initializable, ReentrancyGuard, EIP712 {
    using BaseAccount for *;
    using SafeERC20 for IERC20;

    // =============== STATE VARIABLES ===================

    BaseAccount.AccountState public accountState;
    mapping(uint256 => bool) public usedNonces;
    mapping(address => BaseAccount.AppPermission) public appPermissions;
    mapping(address => BaseAccount.GasPolicy) public gasPolicies;

    address[] public authorizedApps;
    address public entryPoint;
    address public paymaster;

    // Recovery mechanism 
    mapping(address => uint256) public recoveryRequests;

    // Session keys for temporary permissions
    mapping(address => uint256) public sessionKeys; // sessionKey => expiry


    // ====================== EVENTS ============================

    event UserOperationExecuted(bytes32 indexed userOpHash, bool indexed success);
    event SessionKeyAdded(address indexed sessionKey, uint256 expiry);
    event SessionKeyRevoked(address indexed sessionKey);
    event PaymasterUpdated(address indexed oldPaymaster, address indexed newPaymaster);
    event EntryPointUpdated(address indexed oldEntryPoint, address indexed newEntryPoint); 
}
