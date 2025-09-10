// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseAccount.sol";
import "../utils/Security.sol";
import "../utils/Validation.sol";
import "../utils/SignatureSecurity.sol";

/**
 * @title BaseSmartAccount
 * @dev EIP-4337 compatible smart account with advanced features
 * Suppoers gasless transactions, app permissions, and recovery mechanisms
 */

contract BaseSmartAccount is Initializable, ReentrancyGuard, EIP712 {
    using BaseAccount for *;
    using SafeERC20 for IERC20;
    using SignatureSecurity for *;

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
    
    // Enhanced security features
    mapping(bytes32 => bool) public usedSignatures; // Signature hash => used
    mapping(address => uint256) public lastSignatureTime; // Address => last signature timestamp
    mapping(address => uint256) public signatureCount; // Address => signature count for rate limiting
    
    // Key rotation support
    mapping(address => uint256) public keyVersion; // Address => key version
    mapping(address => mapping(uint256 => bool)) public revokedKeys; // Address => version => revoked

    // ====================== EVENTS ============================

    event UserOperationExecuted(bytes32 indexed userOpHash, bool indexed success);
    event SessionKeyAdded(address indexed sessionKey, uint256 expiry);
    event SessionKeyRevoked(address indexed sessionKey);
    event PaymasterUpdated(address indexed oldPaymaster, address indexed newPaymaster);
    event EntryPointUpdated(address indexed oldEntryPoint, address indexed newEntryPoint);
    event SignatureVerified(address indexed signer, bytes32 indexed signatureHash, bool success);
    event KeyRotated(address indexed account, uint256 oldVersion, uint256 newVersion);
    event KeyRevoked(address indexed account, uint256 version);
    event ReplayAttackDetected(address indexed attacker, bytes32 indexed signatureHash);
    event NonceUsed(uint256 indexed nonce, address indexed signer);
    event NoncesCleanedUp(uint256[] nonces);

    // ====================== MODIFIERS ====================

    modifier onlyOwner() {
        require(msg.sender == accountState.owner, "Not owner");
        _;
    }

    modifier onlyOwnerOrAuthorized() {
        require(
            msg.sender == accountState.owner ||
                appPermissions[msg.sender].authorized ||
                (sessionKeys[msg.sender] > 0 && sessionKeys[msg.sender] > block.timestamp),
            "Not authorized"
        );
        _;
    }

    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "Not entry point");
        _;
    }

    modifier notLocked() {
        require(!BaseAccount.shouldBeLocked(accountState), "Account is locked");
        _;
    }

    // ====================== INITIALIZATION ====================

    constructor() EIP712("BaseSmartAccount", "1") {
        // Prevent implementation from being initialized
        _disableInitializers();
    }

    /**
     * @dev Initializes the smart account
     */
    function initialize(address _owner, address _entryPoint) external initializer {
        require(_owner != address(0), "Invalid owner");
        require(_entryPoint != address(0), "Invalid entry point");

        accountState.owner = _owner;
        accountState.nonce = 0;
        accountState.locked = false;
        accountState.recoveryDelay = 1 days;

        entryPoint = _entryPoint;

        emit BaseAccount.AccountCreated(address(this), _owner);
    }

    // ====================== EIP-4337 IMPLEMENTATION  ====================

    /**
     * @dev Validate user operation signature and nonce with enhanced security
     */
    function validateUserOp(
        BaseAccount.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        // Validate basic user operation structure
        require(BaseAccount.validateUserOperation(userOp), "Invalid user operation");
        
        // Check if account is locked
        if (BaseAccount.shouldBeLocked(accountState)) {
            return 1; // Invalid
        }
        
        // Enhanced nonce validation
        if (!_validateNonce(userOp.nonce)) {
            return 1; // Invalid nonce
        }
        
        // Enhanced signature validation with comprehensive security checks
        (address recovered, bool validSignature) = _validateSignature(
            userOpHash, 
            userOp.signature, 
            userOp.sender
        );
        
        if (!validSignature) {
            emit SignatureVerified(recovered, keccak256(userOp.signature), false);
            return 1; // Invalid signature
        }
        
        // Check if key is revoked
        if (_isKeyRevoked(recovered)) {
            emit SignatureVerified(recovered, keccak256(userOp.signature), false);
            return 1; // Key revoked
        }
        
        // Check gas policies if caller is an app
        if (recovered != accountState.owner) {
            BaseAccount.GasPolicy storage policy = gasPolicies[recovered];
            if (!BaseAccount.checkGasPolicy(policy, userOp.callGasLimit, userOp.maxFeePerGas)) {
                return 1; // Gas policy violation
            }
        }
        
        // Pay for missing account funds
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            require(success, "Failed to pay for user operation");
        }
        
        // Mark nonce as used and increment only after successful validation
        usedNonces[userOp.nonce] = true;
        accountState.nonce++;
        
        // Update signature tracking
        _updateSignatureTracking(recovered, keccak256(userOp.signature));
        
        emit NonceUsed(userOp.nonce, recovered);
        emit SignatureVerified(recovered, keccak256(userOp.signature), true);
        return 0; // Valid
    }

    /**
     * @dev Execute user operation
     */
    function executeUserOp(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyEntryPoint notLocked returns (bool success) {
        uint256 gasStart = gasleft();
        
        (success,) = target.call{value: value}(data);
        
        // Update gas spending for policies
        uint256 gasUsed = gasStart - gasleft();
        _updateGasSpending(msg.sender, gasUsed, tx.gasprice);
        
        emit BaseAccount.TransactionExecuted(address(this), keccak256(data), success, gasUsed);
        return success;
    }

    // ============ DIRECT EXECUTION ============

    /**
     * @dev Execute transaction directly (not through entry point)
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyOwnerOrAuthorized notLocked nonReentrant returns (bool success) {
        uint256 gasStart = gasleft();
        
        // Check app permissions if not owner
        if (msg.sender != accountState.owner) {
            BaseAccount.AppPermission storage permission = appPermissions[msg.sender];
            bytes4 methodSelector = BaseAccount.getMethodSelector(data);
            
            require(
                BaseAccount.validateAppPermission(permission, methodSelector, gasStart),
                "App permission denied"
            );
        }
        
        // CRITICAL FIX: Validate gas policies before execution
        require(_validateGasPolicies(msg.sender, gasStart, tx.gasprice), "Gas policy violation");
        
        (success,) = target.call{value: value}(data);
        
        uint256 gasUsed = gasStart - gasleft();
        _updateGasSpending(msg.sender, gasUsed, tx.gasprice);
        
        emit BaseAccount.TransactionExecuted(address(this), keccak256(data), success, gasUsed);
        return success;
    }

    /**
     * @dev Execute multiple transactions in batch
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyOwnerOrAuthorized notLocked nonReentrant returns (bool[] memory results) {
        require(targets.length == values.length && values.length == datas.length, "Array length mismatch");
        
        results = new bool[](targets.length);
        uint256 gasStart = gasleft();
        
        // CRITICAL FIX: Validate gas policies before batch execution
        require(_validateGasPolicies(msg.sender, gasStart, tx.gasprice), "Gas policy violation");
        
        for (uint256 i = 0; i < targets.length; i++) {
            (results[i],) = targets[i].call{value: values[i]}(datas[i]);
            emit BaseAccount.TransactionExecuted(address(this), keccak256(datas[i]), results[i], 0);
        }
        
        uint256 gasUsed = gasStart - gasleft();
        _updateGasSpending(msg.sender, gasUsed, tx.gasprice);
    }

    // ============ APP AUTHORIZATION ============

    /**
     * @dev Authorize an app with specific permissions
     */
    function authorizeApp(
        address app,
        bool authorized,
        uint256 gasAllowance,
        bytes4[] calldata allowedMethods,
        bool requiresConfirmation
    ) external onlyOwner {
        if (authorized && !appPermissions[app].authorized) {
            authorizedApps.push(app);
        } else if (!authorized && appPermissions[app].authorized) {
            // Remove from array
            for (uint256 i = 0; i < authorizedApps.length; i++) {
                if (authorizedApps[i] == app) {
                    authorizedApps[i] = authorizedApps[authorizedApps.length - 1];
                    authorizedApps.pop();
                    break;
                }
            }
        }
        
        appPermissions[app] = BaseAccount.AppPermission({
            authorized: authorized,
            gasAllowance: gasAllowance,
            dailySpentByApp: 0,
            lastAppResetTime: block.timestamp,
            allowedMethods: allowedMethods,
            requiresConfirmation: requiresConfirmation
        });
        
        emit BaseAccount.AppAuthorized(address(this), app, authorized);
    }

    /**
     * @dev Update app gas allowance
     */
    function updateAppGasAllowance(address app, uint256 newAllowance) external onlyOwner {
        require(appPermissions[app].authorized, "App not authorized");
        appPermissions[app].gasAllowance = newAllowance;
    }

    // ============ GAS POLICIES ============

    /**
     * @dev Set gas policy for the account
     */
    function setGasPolicy(
        address paymentToken,
        uint256 maxGasPrice,
        uint256 dailyGasLimit,
        uint256 perTxGasLimit
    ) external onlyOwner {
        gasPolicies[address(this)] = BaseAccount.GasPolicy({
            paymentToken: paymentToken,
            maxGasPrice: maxGasPrice,
            dailyGasLimit: dailyGasLimit,
            perTxGasLimit: perTxGasLimit,
            dailySpent: 0,
            lastResetTime: block.timestamp,
            enabled: true
        });
        
        emit BaseAccount.GasPolicyUpdated(address(this), paymentToken, dailyGasLimit);
    }

    /**
     * @dev Set app-specific gas policy
     */
    function setAppGasPolicy(
        address app,
        address paymentToken,
        uint256 maxGasPrice,
        uint256 dailyGasLimit,
        uint256 perTxGasLimit
    ) external onlyOwner {
        require(appPermissions[app].authorized, "App not authorized");
        
        gasPolicies[app] = BaseAccount.GasPolicy({
            paymentToken: paymentToken,
            maxGasPrice: maxGasPrice,
            dailyGasLimit: dailyGasLimit,
            perTxGasLimit: perTxGasLimit,
            dailySpent: 0,
            lastResetTime: block.timestamp,
            enabled: true
        });
        
        emit BaseAccount.GasPolicyUpdated(address(this), paymentToken, dailyGasLimit);
    }

    // ============ SESSION KEYS ============

    /**
     * @dev Add session key with expiry and gas policy
     */
    function addSessionKey(
        address sessionKey, 
        uint256 duration,
        address paymentToken,
        uint256 maxGasPrice,
        uint256 dailyGasLimit,
        uint256 perTxGasLimit
    ) external onlyOwner {
        require(sessionKey != address(0), "Invalid session key");
        require(duration > 0 && duration <= 30 days, "Invalid duration");
        
        uint256 expiry = block.timestamp + duration;
        sessionKeys[sessionKey] = expiry;
        
        // Set gas policy for session key
        gasPolicies[sessionKey] = BaseAccount.GasPolicy({
            paymentToken: paymentToken,
            maxGasPrice: maxGasPrice,
            dailyGasLimit: dailyGasLimit,
            perTxGasLimit: perTxGasLimit,
            dailySpent: 0,
            lastResetTime: block.timestamp,
            enabled: true
        });
        
        emit SessionKeyAdded(sessionKey, expiry);
        emit BaseAccount.GasPolicyUpdated(sessionKey, paymentToken, dailyGasLimit);
    }

    /**
     * @dev Revoke session key
     */
    function revokeSessionKey(address sessionKey) external onlyOwner {
        delete sessionKeys[sessionKey];
        // Also clear gas policy for revoked session key
        delete gasPolicies[sessionKey];
        emit SessionKeyRevoked(sessionKey);
    }
    
    /**
     * @dev Set gas policy for session key
     */
    function setSessionKeyGasPolicy(
        address sessionKey,
        address paymentToken,
        uint256 maxGasPrice,
        uint256 dailyGasLimit,
        uint256 perTxGasLimit
    ) external onlyOwner {
        require(sessionKeys[sessionKey] > 0, "Session key not found");
        
        gasPolicies[sessionKey] = BaseAccount.GasPolicy({
            paymentToken: paymentToken,
            maxGasPrice: maxGasPrice,
            dailyGasLimit: dailyGasLimit,
            perTxGasLimit: perTxGasLimit,
            dailySpent: 0,
            lastResetTime: block.timestamp,
            enabled: true
        });
        
        emit BaseAccount.GasPolicyUpdated(sessionKey, paymentToken, dailyGasLimit);
    }

    // ============ KEY ROTATION & REVOCATION ============

    /**
     * @dev Rotate key for enhanced security
     */
    function rotateKey(address newKey) external onlyOwner {
        require(newKey != address(0), "Invalid new key");
        require(newKey != accountState.owner, "Same key");
        
        uint256 oldVersion = keyVersion[accountState.owner];
        uint256 newVersion = oldVersion + 1;
        
        // Revoke old key
        revokedKeys[accountState.owner][oldVersion] = true;
        
        // Set new key
        accountState.owner = newKey;
        keyVersion[newKey] = newVersion;
        
        // Invalidate all pending operations
        accountState.nonce++;
        
        emit KeyRotated(newKey, oldVersion, newVersion);
    }
    
    /**
     * @dev Revoke a specific key version
     */
    function revokeKey(address key, uint256 version) external onlyOwner {
        require(key != address(0), "Invalid key");
        
        revokedKeys[key][version] = true;
        emit KeyRevoked(key, version);
    }
    
    /**
     * @dev Emergency key rotation with shorter delay
     */
    function emergencyKeyRotation(address newKey) external onlyOwner {
        require(newKey != address(0), "Invalid new key");
        require(newKey != accountState.owner, "Same key");
        
        // Immediate rotation for emergency
        uint256 oldVersion = keyVersion[accountState.owner];
        uint256 newVersion = oldVersion + 1;
        
        revokedKeys[accountState.owner][oldVersion] = true;
        accountState.owner = newKey;
        keyVersion[newKey] = newVersion;
        accountState.nonce++;
        
        emit KeyRotated(newKey, oldVersion, newVersion);
    }

    // ============ RECOVERY MECHANISM ============

    /**
     * @dev Set recovery address and delay
     */
    function setRecovery(address recovery, uint256 delay) external onlyOwner {
        require(BaseAccount.validateRecovery(delay, recovery, accountState.owner), "Invalid recovery");
        
        accountState.recovery = recovery;
        accountState.recoveryDelay = delay;
    }

    /**
     * @dev Initiate recovery process
     */
    function initiateRecovery(address newOwner) external {
        require(msg.sender == accountState.recovery, "Not recovery address");
        require(newOwner != address(0), "Invalid new owner");
        require(newOwner != accountState.owner, "Same owner");
        
        recoveryRequests[newOwner] = block.timestamp;
        emit BaseAccount.RecoveryInitiated(address(this), newOwner);
    }

    /**
     * @dev Complete recovery process
     */
    function completeRecovery(address newOwner) external {
        require(msg.sender == accountState.recovery, "Not recovery address");
        require(recoveryRequests[newOwner] != 0, "No recovery request");
        require(
            block.timestamp >= recoveryRequests[newOwner] + accountState.recoveryDelay,
            "Recovery delay not met"
        );
        
        address oldOwner = accountState.owner;
        accountState.owner = newOwner;
        accountState.nonce++; // Invalidate pending operations
        
        // Clear recovery request
        delete recoveryRequests[newOwner];
        
        // Clear all app authorizations for security
        for (uint256 i = 0; i < authorizedApps.length; i++) {
            delete appPermissions[authorizedApps[i]];
        }
        delete authorizedApps;
        
        emit BaseAccount.AccountCreated(address(this), newOwner);
    }

    // ============ EMERGENCY FUNCTIONS ============

    /**
     * @dev Lock account in emergency
     */
    function lockAccount(uint256 duration) external onlyOwner {
        require(duration <= BaseAccount.MAX_LOCK_DURATION, "Lock duration too long");
        
        accountState.locked = true;
        accountState.lockUntil = block.timestamp + duration;
        
        emit BaseAccount.AccountLocked(address(this), accountState.lockUntil);
    }

    /**
     * @dev Unlock account
     */
    function unlockAccount() external onlyOwner {
        accountState.locked = false;
        accountState.lockUntil = 0;
    }

    // ============ PAYMASTER INTEGRATION ============

    /**
     * @dev Set paymaster for gas sponsorship
     */
    function setPaymaster(address _paymaster) external onlyOwner {
        address oldPaymaster = paymaster;
        paymaster = _paymaster;
        emit PaymasterUpdated(oldPaymaster, _paymaster);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Enhanced signature validation with comprehensive security checks
     */
    function _validateSignature(
        bytes32 userOpHash,
        bytes calldata signature,
        address sender
    ) internal returns (address recovered, bool valid) {
        // Validate signature format
        Validation.validateSignature(signature);
        
        // Check for signature malleability
        if (_isSignatureMalleable(signature)) {
            return (address(0), false);
        }
        
        // Check if signature was already used (replay protection)
        bytes32 signatureHash = keccak256(signature);
        if (usedSignatures[signatureHash]) {
            emit ReplayAttackDetected(sender, signatureHash);
            return (address(0), false);
        }
        
        // Recover signer with enhanced validation
        try ECDSA.recover(userOpHash, signature) returns (address signer) {
            recovered = signer;
            
            // Validate recovered address
            if (recovered == address(0)) {
                return (address(0), false);
            }
            
            // Check authorization
            valid = (recovered == accountState.owner) || 
                   appPermissions[recovered].authorized ||
                   (sessionKeys[recovered] > 0 && sessionKeys[recovered] > block.timestamp);
            
            // Rate limiting check
            if (valid && !_checkSignatureRateLimit(recovered)) {
                return (recovered, false);
            }
            
        } catch {
            return (address(0), false);
        }
    }
    
    /**
     * @dev Enhanced nonce validation with additional security checks
     */
    function _validateNonce(uint256 nonce) internal view returns (bool) {
        // Check if nonce was already used
        if (usedNonces[nonce]) {
            return false;
        }
        
        // Only accept the exact current nonce (strict sequential nonce validation)
        if (nonce != accountState.nonce) {
            return false;
        }
        
        return true;
    }
    
    /**
     * @dev Check if signature is malleable (security vulnerability)
     */
    function _isSignatureMalleable(bytes calldata signature) internal pure returns (bool) {
        if (signature.length != 65) return true;
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        
        // Check for signature malleability
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return true;
        }
        
        return false;
    }
    
    /**
     * @dev Check signature rate limiting
     */
    function _checkSignatureRateLimit(address signer) internal view returns (bool) {
        // Allow up to 100 signatures per hour per signer
        uint256 timeWindow = 1 hours;
        uint256 maxSignatures = 100;
        
        if (block.timestamp - lastSignatureTime[signer] > timeWindow) {
            return true; // Time window reset
        }
        
        return signatureCount[signer] < maxSignatures;
    }
    
    /**
     * @dev Update signature tracking for security monitoring
     */
    function _updateSignatureTracking(address signer, bytes32 signatureHash) internal {
        // Mark signature as used
        usedSignatures[signatureHash] = true;
        
        // Update rate limiting counters
        if (block.timestamp - lastSignatureTime[signer] > 1 hours) {
            signatureCount[signer] = 0;
        }
        
        signatureCount[signer]++;
        lastSignatureTime[signer] = block.timestamp;
    }
    
    /**
     * @dev Check if key is revoked
     */
    function _isKeyRevoked(address signer) internal view returns (bool) {
        uint256 currentVersion = keyVersion[signer];
        return revokedKeys[signer][currentVersion];
    }

    /**
     * @dev Comprehensive gas policy validation for all execution paths
     */
    function _validateGasPolicies(address caller, uint256 gasLimit, uint256 gasPrice) internal view returns (bool) {
        // Always validate account-level gas policy
        BaseAccount.GasPolicy storage accountPolicy = gasPolicies[address(this)];
        if (!BaseAccount.checkGasPolicy(accountPolicy, gasLimit, gasPrice)) {
            return false;
        }
        
        // For non-owner callers, validate app-specific gas policies
        if (caller != accountState.owner) {
            // Check if caller is an authorized app
            if (appPermissions[caller].authorized) {
                BaseAccount.GasPolicy storage appPolicy = gasPolicies[caller];
                if (!BaseAccount.checkGasPolicy(appPolicy, gasLimit, gasPrice)) {
                    return false;
                }
            }
            // Check if caller is a valid session key
            else if (sessionKeys[caller] > 0 && sessionKeys[caller] > block.timestamp) {
                // Session keys must also respect gas policies
                BaseAccount.GasPolicy storage sessionPolicy = gasPolicies[caller];
                if (!BaseAccount.checkGasPolicy(sessionPolicy, gasLimit, gasPrice)) {
                    return false;
                }
            }
            // If caller is neither authorized app nor valid session key, deny
            else {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @dev Update gas spending for policies
     */
    function _updateGasSpending(address caller, uint256 gasUsed, uint256 gasPrice) internal {
        // Update account-level gas policy
        BaseAccount.GasPolicy storage accountPolicy = gasPolicies[address(this)];
        BaseAccount.updateGasSpending(accountPolicy, gasUsed, gasPrice);
        
        // Update app-specific gas policy if applicable
        if (caller != accountState.owner && appPermissions[caller].authorized) {
            BaseAccount.GasPolicy storage appPolicy = gasPolicies[caller];
            BaseAccount.updateGasSpending(appPolicy, gasUsed, gasPrice);
            
            // Update app permission gas spending
            BaseAccount.updateAppGasSpending(appPermissions[caller], gasUsed, gasPrice);
        }
        
        // Update session key gas policy if applicable
        if (caller != accountState.owner && sessionKeys[caller] > 0 && sessionKeys[caller] > block.timestamp) {
            BaseAccount.GasPolicy storage sessionPolicy = gasPolicies[caller];
            BaseAccount.updateGasSpending(sessionPolicy, gasUsed, gasPrice);
        }
    }

    // ============ NONCE MANAGEMENT ============

    /**
     * @dev Clean up old nonces to prevent storage bloat
     * @param nonces Array of nonces to clean up (must be < current nonce)
     */
    function cleanupNonces(uint256[] calldata nonces) external onlyOwner {
        uint256 currentNonce = accountState.nonce;
        uint256 cleanedCount = 0;
        
        for (uint256 i = 0; i < nonces.length; i++) {
            uint256 nonce = nonces[i];
            // Only allow cleanup of nonces that are significantly older than current
            if (nonce < currentNonce - 1000) {
                delete usedNonces[nonce];
                cleanedCount++;
            }
        }
        
        if (cleanedCount > 0) {
            emit NoncesCleanedUp(nonces);
        }
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get next valid nonce
     */
    function getNonce() external view returns (uint256) {
        return accountState.nonce;
    }

    /**
     * @dev Check if app is authorized
     */
    function isAuthorizedApp(address app) external view returns (bool) {
        return appPermissions[app].authorized;
    }

    /**
     * @dev Get app permission details
     */
    function getAppPermission(address app) external view returns (BaseAccount.AppPermission memory) {
        return appPermissions[app];
    }

    /**
     * @dev Get gas policy details
     */
    function getGasPolicy(address target) external view returns (BaseAccount.GasPolicy memory) {
        return gasPolicies[target];
    }

    /**
     * @dev Get all authorized apps
     */
    function getAuthorizedApps() external view returns (address[] memory) {
        return authorizedApps;
    }

    /**
     * @dev Check if session key is valid
     */
    function isValidSessionKey(address sessionKey) external view returns (bool) {
        return sessionKeys[sessionKey] > 0 && 
               sessionKeys[sessionKey] > block.timestamp &&
               !_isKeyRevoked(sessionKey);
    }
    
    /**
     * @dev Get key version for an address
     */
    function getKeyVersion(address key) external view returns (uint256) {
        return keyVersion[key];
    }
    
    /**
     * @dev Check if a key version is revoked
     */
    function isKeyRevoked(address key, uint256 version) external view returns (bool) {
        return revokedKeys[key][version];
    }
    
    /**
     * @dev Get signature count for rate limiting
     */
    function getSignatureCount(address signer) external view returns (uint256) {
        if (block.timestamp - lastSignatureTime[signer] > 1 hours) {
            return 0; // Reset
        }
        return signatureCount[signer];
    }
    
    /**
     * @dev Check if signature was used (replay protection)
     */
    function isSignatureUsed(bytes32 signatureHash) external view returns (bool) {
        return usedSignatures[signatureHash];
    }

    // ============ RECEIVE FUNCTIONS ============

    /**
     * @dev Receive ETH
     */
    receive() external payable {
        // Accept ETH
    }

    /**
     * @dev Fallback function
     */
    fallback() external payable {
        // Accept ETH and calls
    }
}
