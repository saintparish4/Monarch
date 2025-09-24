// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Constants
 * @dev Common constants used across MonarchKit gasless modules
 * @notice Centralized constant values for consistency and gas optimization
 */
library Constants {
    // Gas limits
    uint256 public constant MAX_CALL_GAS_LIMIT = 5_000_000;
    uint256 public constant MAX_VERIFICATION_GAS = 1_000_000;
    uint256 public constant MAX_PRE_VERIFICATION_GAS = 100_000;
    uint256 public constant MIN_GAS_LIMIT = 21_000;

    // Time constants
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant SECONDS_PER_MONTH = 2_592_000; // 30 days
    uint256 public constant MAX_SUBSCRIPTION_DURATION = 31_536_000; // 365 days

    // Signature constants
    uint256 public constant SIGNATURE_LENGTH = 65;
    bytes32 public constant EIP712_DOMAIN_TYPEHASH = 
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant USER_OPERATION_TYPEHASH = 
        keccak256("UserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,uint256 callGasLimit,uint256 verificationGasLimit,uint256 preVerificationGas,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,bytes paymasterAndData)");

    // Account abstraction constants
    address public constant ENTRY_POINT_V0_6 = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address public constant ENTRY_POINT_V0_7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    // Validation constants
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;
    uint256 public constant SIG_VALIDATION_FAILED = 1;

    // Paymaster constants
    uint256 public constant MIN_MONTHLY_LIMIT = 0.001 ether; // Minimum monthly gas limit
    uint256 public constant MAX_MONTHLY_LIMIT = 10 ether;    // Maximum monthly gas limit
    uint256 public constant MIN_DEPOSIT = 0.0001 ether;     // Minimum deposit amount

    // Factory constants
    bytes32 public constant ACCOUNT_INIT_CODE_HASH = 
        keccak256("BaseSmartAccount");
    uint256 public constant ACCOUNT_CREATION_SALT = 0;

    // Error messages
    string public constant ERR_INVALID_SIGNATURE = "Invalid signature";
    string public constant ERR_INSUFFICIENT_GAS = "Insufficient gas";
    string public constant ERR_UNAUTHORIZED = "Unauthorized access";
    string public constant ERR_INVALID_OPERATION = "Invalid operation";
    string public constant ERR_EXECUTION_FAILED = "Execution failed";

    // Module identifiers
    string public constant MODULE_TYPE_GASLESS = "gasless";
    string public constant MODULE_TYPE_PAYMENTS = "payments";
    string public constant MODULE_TYPE_SOCIAL = "social";

    // EIP-2771 constants
    bytes32 public constant META_TRANSACTION_TYPEHASH = 
        keccak256("MetaTransaction(uint256 nonce,address from,bytes functionSignature)");

    /**
     * @notice Calculate account address salt
     * @param owner The account owner
     * @param index The account index for the owner
     * @return salt The calculated salt
     */
    function calculateAccountSalt(address owner, uint256 index) internal pure returns (bytes32 salt) {
        return keccak256(abi.encodePacked(owner, index, ACCOUNT_CREATION_SALT));
    }

    /**
     * @notice Check if gas limits are within bounds
     * @param callGasLimit The call gas limit
     * @param verificationGasLimit The verification gas limit
     * @param preVerificationGas The pre-verification gas
     * @return valid True if all limits are valid
     */
    function validateGasLimits(
        uint256 callGasLimit,
        uint256 verificationGasLimit,
        uint256 preVerificationGas
    ) internal pure returns (bool valid) {
        return callGasLimit <= MAX_CALL_GAS_LIMIT &&
               callGasLimit >= MIN_GAS_LIMIT &&
               verificationGasLimit <= MAX_VERIFICATION_GAS &&
               preVerificationGas <= MAX_PRE_VERIFICATION_GAS;
    }

    /**
     * @notice Calculate the current month timestamp
     * @return monthStart Timestamp of the current month start
     */
    function getCurrentMonthStart() internal view returns (uint256 monthStart) {
        uint256 currentTime = block.timestamp;
        return currentTime - (currentTime % SECONDS_PER_MONTH);
    }

    /**
     * @notice Check if a timestamp is in the current month
     * @param timestamp The timestamp to check
     * @return inCurrentMonth True if timestamp is in current month
     */
    function isInCurrentMonth(uint256 timestamp) internal view returns (bool inCurrentMonth) {
        uint256 monthStart = getCurrentMonthStart();
        return timestamp >= monthStart && timestamp < monthStart + SECONDS_PER_MONTH;
    }
}