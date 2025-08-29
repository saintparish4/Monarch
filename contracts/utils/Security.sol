// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Security
 * @dev Security utilities and access control patterns for Base applications
 * @author BlueSky Labs Contracts Team
 */
library Security {
    // Custom errors for gas efficiency
    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error ContractPaused();
    error DeadlineExpired();
    error InvalidSignature();
    error NonceAlreadyUsed();

    /**
     * @dev Modifier data structure for role-based access control
     */
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    /**
     * @dev Pause functionality state
     */
    struct PauseData {
        bool paused;
        address pauser;
        uint256 pausedAt;
    }

    /**
     * @dev Rate limiting data structure
     */
    struct RateLimit {
        uint256 lastAction;
        uint256 actionCount;
        uint256 windowStart;
        uint256 limit;
        uint256 window;
    }

    /**
     * @dev Nonce tracking for replay protection
     */
    struct NonceTracker {
        mapping(address => uint256) nonces;
        mapping(address => mapping(uint256 => bool)) usedNonces;
    }

    // Events
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);
    event RateLimitExceeded(address indexed account, uint256 limit);

    /**
     * @dev Grants role to account
     */
    function grantRole(
        mapping(bytes32 => RoleData) storage roles,
        bytes32 role,
        address account,
        address admin
    ) internal {
        if (!hasRole(roles, roles[role].adminRole, admin)) {
            revert Unauthorized();
        }

        if (!roles[role].members[account]) {
            roles[role].members[account] = true;
            emit RoleGranted(role, account, admin);
        }
    }

    /**
     * @dev Revokes role from account
     */
    function revokeRole(
        mapping(bytes32 => RoleData) storage roles,
        bytes32 role,
        address account,
        address admin
    ) internal {
        if (!hasRole(roles, roles[role].adminRole, admin)) {
            revert Unauthorized();
        }

        if (roles[role].members[account]) {
            roles[role].members[account] = false;
            emit RoleRevoked(role, account, admin);
        }
    }

    /**
     * @dev Checks if account has role
     */
    function hasRole(
        mapping(bytes32 => RoleData) storage roles,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return roles[role].members[account];
    }

    /**
     * @dev Requires that caller has specific role
     */
    function requireRole(mapping(bytes32 => RoleData) storage roles, bytes32 role, address account) internal view {
        if (!hasRole(roles, role, account)) {
            revert Unauthorized();
        }
    }

    /**
     * @dev Pauses contract functionality
     */
    function pause(PauseData storage pauseData, address pauser) internal {
        pauseData.paused = true;
        pauseData.pauser = pauser;
        pauseData.pausedAt = block.timestamp;
        emit Paused(pauser);
    }

    /**
     * @dev Unpauses contract functionality
     */
    function unpause(PauseData storage pauseData, address pauser) internal {
        pauseData.paused = false;
        pauseData.pauser = pauser;
        pauseData.pausedAt = 0;
        emit Unpaused(pauser);
    }

    /**
     * @dev Requires that contract is not paused
     */
    function requireNotPaused(PauseData storage pauseData) internal view {
        if (pauseData.paused) {
            revert ContractPaused();
        }
    }

    /**
     * @dev Validates address is not zero
     */
    function requireValidAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert InvalidAddress();
        }
    }

    /**
     * @dev Validates amount is greater than zero
     */
    function requireValidAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert InvalidAmount();
        }
    }

    /**
     * @dev Validates deadline has not expired
     */
    function requireNotExpired(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert DeadlineExpired();
        }
    }

    /**
     * @dev Checks rate limit for an account
     */
    function checkRateLimit(
        mapping(address => RateLimit) storage rateLimits,
        address account,
        uint256 limit,
        uint256 window
    ) internal {
        RateLimit storage userLimit = rateLimits[account];

        // Initialize if first time
        if (userLimit.limit == 0) {
            userLimit.limit = limit;
            userLimit.window = window;
            userLimit.windowStart = block.timestamp;
            userLimit.actionCount = 0;
        }

        // Reset window if expired
        if (block.timestamp >= userLimit.windowStart + userLimit.window) {
            userLimit.windowStart = block.timestamp;
            userLimit.actionCount = 0;
        }

        // Check if limit exceeded
        if (userLimit.actionCount >= userLimit.limit) {
            emit RateLimitExceeded(account, limit);
            revert("Rate limit exceeded");
        }

        // Increment counter
        userLimit.actionCount++;
        userLimit.lastAction = block.timestamp;
    }

    /**
     * @dev Gets next nonce for account
     */
    function getNextNonce(NonceTracker storage tracker, address account) internal view returns (uint256) {
        return tracker.nonces[account];
    }

    /**
     * @dev Uses a nonce (marks it as used and increments)
     */
    function useNonce(NonceTracker storage tracker, address account, uint256 nonce) internal {
        if (nonce != tracker.nonces[account]) {
            revert NonceAlreadyUsed();
        }

        tracker.usedNonces[account][nonce] = true;
        tracker.nonces[account]++;
    }

    /**
     * @dev Checks if a nonce has been used
     */
    function isNonceUsed(NonceTracker storage tracker, address account, uint256 nonce) internal view returns (bool) {
        return tracker.usedNonces[account][nonce];
    }

    /**
     * @dev Validates signature using ECDSA
     */
    function validateSignature(bytes32 hash, bytes memory signature, address expectedSigner) internal pure {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(hash);
        address signer = recoverSigner(ethSignedMessageHash, signature);

        if (signer != expectedSigner) {
            revert InvalidSignature();
        }
    }

    /**
     * @dev Creates ETH signed message hash
     */
    function getEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    /**
     * @dev Recovers signer from signature
     */
    function recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        return ecrecover(hash, v, r, s);
    }

    /**
     * @dev Safe transfer of ETH
     */
    function safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @dev Validates that an address is a contract
     */
    function requireContract(address addr) internal view {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        require(size > 0, "Address is not a contract");
    }

    /**
     * @dev Validates that an address is an EOA (not a contract)
     */
    function requireEOA(address addr) internal view {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        require(size == 0, "Address must be EOA");
    }

    /**
     * @dev Time-based access control - only allows calls within time window
     */
    function requireTimeWindow(uint256 startTime, uint256 endTime) internal view {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Outside time window");
    }

    /**
     * @dev Validates that a value is within a percentage range of expected
     */
    function requireWithinPercentage(uint256 actual, uint256 expected, uint256 toleranceBps) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        uint256 maxDiff = (expected * toleranceBps) / 10000;
        require(diff <= maxDiff, "Value outside tolerance");
    }

    /**
     * @dev Validates array length matching
     */
    function requireSameLength(uint256 length1, uint256 length2) internal pure {
        require(length1 == length2, "Array length mismatch");
    }

    /**
     * @dev Validates maximum array length
     */
    function requireMaxLength(uint256 length, uint256 maxLength) internal pure {
        require(length <= maxLength, "Array too long");
    }
}
