// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Constants
 * @dev Common constants used across Base contract libraries
 * @author BlueSky Labs Contracts Team
 */
library Constants {
    // ============ MATHEMATICAL CONSTANTS ============

    /// @dev 100% in basis points
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;

    /// @dev Maximum basis points (100%)
    uint256 public constant MAX_BASIS_POINTS = 10000;

    /// @dev Precision for calculations (18 decimals)
    uint256 public constant PRECISION = 1e18;

    /// @dev Minimum liquidity locked in AMM pools
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // ============ TIME CONSTANTS ============

    /// @dev Seconds in a minute
    uint256 public constant SECONDS_PER_MINUTE = 60;

    /// @dev Seconds in an hour
    uint256 public constant SECONDS_PER_HOUR = 3600;

    /// @dev Seconds in a day
    uint256 public constant SECONDS_PER_DAY = 86400;

    /// @dev Seconds in a week
    uint256 public constant SECONDS_PER_WEEK = 604800;

    /// @dev Seconds in a year (365 days)
    uint256 public constant SECONDS_PER_YEAR = 31536000;

    /// @dev Default grace period for failed payments
    uint256 public constant DEFAULT_GRACE_PERIOD = 3 days;

    /// @dev Maximum auction duration
    uint256 public constant MAX_AUCTION_DURATION = 30 days;

    /// @dev Minimum auction duration
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;

    // ============ GAS CONSTANTS ============

    /// @dev Base L2 block gas limit
    uint256 public constant BASE_BLOCK_GAS_LIMIT = 15000000;

    /// @dev Maximum gas limit for user operations
    uint256 public constant MAX_OPERATION_GAS_LIMIT = 5000000;

    /// @dev Minimum gas limit for transactions
    uint256 public constant MIN_GAS_LIMIT = 21000;

    /// @dev Gas buffer for complex operations
    uint256 public constant GAS_BUFFER = 50000;

    // ============ FEE CONSTANTS ============

    /// @dev Default platform fee (2.5%)
    uint256 public constant DEFAULT_PLATFORM_FEE = 250;

    /// @dev Maximum platform fee (10%)
    uint256 public constant MAX_PLATFORM_FEE = 1000;

    /// @dev Default DEX fee (0.3%)
    uint256 public constant DEFAULT_DEX_FEE = 30;

    /// @dev Maximum DEX fee (1%)
    uint256 public constant MAX_DEX_FEE = 100;

    /// @dev Default royalty fee (5%)
    uint256 public constant DEFAULT_ROYALTY_FEE = 500;

    /// @dev Maximum royalty fee (10%)
    uint256 public constant MAX_ROYALTY_FEE = 1000;

    // ============ STRING LENGTH CONSTANTS ============

    /// @dev Maximum string length for general use
    uint256 public constant MAX_STRING_LENGTH = 1000;

    /// @dev Maximum handle length
    uint256 public constant MAX_HANDLE_LENGTH = 32;

    /// @dev Minimum handle length
    uint256 public constant MIN_HANDLE_LENGTH = 3;

    /// @dev Maximum token name length
    uint256 public constant MAX_TOKEN_NAME_LENGTH = 50;

    /// @dev Maximum token symbol length
    uint256 public constant MAX_TOKEN_SYMBOL_LENGTH = 11;

    /// @dev Minimum token symbol length
    uint256 public constant MIN_TOKEN_SYMBOL_LENGTH = 2;

    /// @dev Maximum bio length
    uint256 public constant MAX_BIO_LENGTH = 500;

    /// @dev Maximum URL length
    uint256 public constant MAX_URL_LENGTH = 2083;

    // ============ ARRAY LENGTH CONSTANTS ============

    /// @dev Maximum array length for batch operations
    uint256 public constant MAX_ARRAY_LENGTH = 1000;

    /// @dev Maximum batch size for processing
    uint256 public constant MAX_BATCH_SIZE = 100;

    // ============ FINANCIAL CONSTANTS ============

    /// @dev Maximum supply for tokens (to prevent overflow)
    uint256 public constant MAX_TOKEN_SUPPLY = type(uint128).max;

    /// @dev Maximum price to prevent overflow in calculations
    uint256 public constant MAX_PRICE = type(uint128).max;

    /// @dev Minimum price for paid content (1 wei)
    uint256 public constant MIN_PRICE = 1;

    /// @dev Default collateralization ratio (150%)
    uint256 public constant DEFAULT_COLLATERAL_RATIO = 15000;

    /// @dev Liquidation threshold (120%)
    uint256 public constant LIQUIDATION_THRESHOLD = 12000;

    // ============ NETWORK CONSTANTS ============

    /// @dev Base Mainnet chain ID
    uint256 public constant BASE_MAINNET_CHAIN_ID = 8453;

    /// @dev Base Goerli chain ID
    uint256 public constant BASE_GOERLI_CHAIN_ID = 84531;

    /// @dev Ethereum Mainnet chain ID
    uint256 public constant ETHEREUM_MAINNET_CHAIN_ID = 1;

    // ============ ACCESS CONTROL ROLES ============

    /// @dev Default admin role
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @dev Minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Pauser role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Verifier role (for social verification)
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @dev Operator role (for automated operations)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Liquidator role (for DeFi liquidations)
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // ============ SIGNATURE CONSTANTS ============

    /// @dev Standard signature length
    uint256 public constant SIGNATURE_LENGTH = 65;

    /// @dev EIP-712 domain separator version
    string public constant DOMAIN_VERSION = "1";

    /// @dev Maximum signature validity period
    uint256 public constant MAX_SIGNATURE_VALIDITY = 1 hours;

    // ============ RATE LIMITING CONSTANTS ============

    /// @dev Default rate limit window (1 hour)
    uint256 public constant DEFAULT_RATE_LIMIT_WINDOW = 1 hours;

    /// @dev Default rate limit count
    uint256 public constant DEFAULT_RATE_LIMIT_COUNT = 100;

    /// @dev Maximum daily gas spending limit (1 ETH worth)
    uint256 public constant MAX_DAILY_GAS_LIMIT = 1 ether;

    // ============ GAMING CONSTANTS ============

    /// @dev Maximum number of tournament participants
    uint256 public constant MAX_TOURNAMENT_PARTICIPANTS = 10000;

    /// @dev Minimum tournament entry fee (to prevent spam)
    uint256 public constant MIN_TOURNAMENT_ENTRY = 0.001 ether;

    /// @dev Maximum tournament duration
    uint256 public constant MAX_TOURNAMENT_DURATION = 7 days;

    // ============ SOCIAL CONSTANTS ============

    /// @dev Maximum number of follows to process in batch
    uint256 public constant MAX_FOLLOW_BATCH = 50;

    /// @dev Social token bonding curve factor
    uint256 public constant BONDING_CURVE_FACTOR = 1000000;

    /// @dev Maximum content price
    uint256 public constant MAX_CONTENT_PRICE = 10 ether;

    // ============ NFT CONSTANTS ============

    /// @dev Maximum NFT collection size
    uint256 public constant MAX_COLLECTION_SIZE = 100000;

    /// @dev Maximum mint batch size
    uint256 public constant MAX_MINT_BATCH = 50;

    /// @dev Minimum auction increment (5%)
    uint256 public constant MIN_AUCTION_INCREMENT = 500;

    // ============ DEFI CONSTANTS ============

    /// @dev Maximum slippage tolerance (50%)
    uint256 public constant MAX_SLIPPAGE = 5000;

    /// @dev Default slippage tolerance (1%)
    uint256 public constant DEFAULT_SLIPPAGE = 100;

    /// @dev Minimum pool liquidity
    uint256 public constant MIN_POOL_LIQUIDITY = 1000;

    /// @dev Maximum interest rate (1000% APR)
    uint256 public constant MAX_INTEREST_RATE = 100000;

    // ============ BRIDGE CONSTANTS ============

    /// @dev Minimum bridge amount to prevent dust
    uint256 public constant MIN_BRIDGE_AMOUNT = 0.001 ether;

    /// @dev Maximum bridge amount per transaction
    uint256 public constant MAX_BRIDGE_AMOUNT = 10000 ether;

    /// @dev Bridge confirmation blocks
    uint256 public constant BRIDGE_CONFIRMATIONS = 12;

    // ============ GOVERNANCE CONSTANTS ============

    /// @dev Voting period (7 days)
    uint256 public constant VOTING_PERIOD = 7 days;

    /// @dev Voting delay (1 day)
    uint256 public constant VOTING_DELAY = 1 days;

    /// @dev Minimum proposal threshold (1%)
    uint256 public constant PROPOSAL_THRESHOLD = 100;

    /// @dev Quorum threshold (4%)
    uint256 public constant QUORUM_THRESHOLD = 400;

    // ============ ERROR MESSAGES ============

    string public constant ERROR_INVALID_ADDRESS = "Invalid address";
    string public constant ERROR_INVALID_AMOUNT = "Invalid amount";
    string public constant ERROR_INSUFFICIENT_BALANCE = "Insufficient balance";
    string public constant ERROR_UNAUTHORIZED = "Unauthorized";
    string public constant ERROR_EXPIRED = "Expired";
    string public constant ERROR_ALREADY_EXISTS = "Already exists";
    string public constant ERROR_NOT_FOUND = "Not found";
    string public constant ERROR_PAUSED = "Contract paused";
    string public constant ERROR_INVALID_SIGNATURE = "Invalid signature";
    string public constant ERROR_RATE_LIMITED = "Rate limited";

    // ============ IPFS CONSTANTS ============

    /// @dev IPFS CIDv0 length
    uint256 public constant IPFS_CID_V0_LENGTH = 46;

    /// @dev IPFS CIDv1 length
    uint256 public constant IPFS_CID_V1_LENGTH = 59;

    // ============ HELPER FUNCTIONS ============

    /**
     * @dev Check if running on Base Mainnet
     */
    function isBaseMainnet() internal view returns (bool) {
        return block.chainid == BASE_MAINNET_CHAIN_ID;
    }

    /**
     * @dev Check if running on Base Goerli
     */
    function isBaseGoerli() internal view returns (bool) {
        return block.chainid == BASE_GOERLI_CHAIN_ID;
    }

    /**
     * @dev Check if running on any Base network
     */
    function isBaseNetwork() internal view returns (bool) {
        return isBaseMainnet() || isBaseGoerli();
    }

    /**
     * @dev Get current year timestamp
     */
    function getCurrentYear() internal view returns (uint256) {
        return (block.timestamp / SECONDS_PER_YEAR) * SECONDS_PER_YEAR;
    }

    /**
     * @dev Convert basis points to percentage
     */
    function bpsToPercentage(uint256 bps) internal pure returns (uint256) {
        return (bps * 100) / BASIS_POINTS_DENOMINATOR;
    }

    /**
     * @dev Convert percentage to basis points
     */
    function percentageToBps(uint256 percentage) internal pure returns (uint256) {
        return (percentage * BASIS_POINTS_DENOMINATOR) / 100;
    }
}
