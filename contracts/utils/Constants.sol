// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title BaseConstants
 * @dev Common constants used across Base contract libraries
 * @author Monarch Contracts Team  
 */ 
library BaseConstants {
    /// @dev Math constants
    uint256 public constant MAX_BPS = 10000; // 100% in basis points
    uint256 public constant PRECISION = 1e18; // 18 decimals for fixed point arithmetic
    uint256 public constant HUNDRED_PERCENT = 1e18; // 100% in 18 decimal 

    /// @dev Time constants
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant SECONDS_PER_HOUR = 3600;
    uint256 public constant SECONDS_PER_WEEK = 604800;
    uint256 public constant SECONDS_PER_MONTH = 2629746; // 30.44 days
    uint256 public constant SECONDS_PER_YEAR = 31556952; // 365.25 days

    /// @dev Minimum time durations
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant MIN_SUBSCRIPTION_PERIOD = 1 days;
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MIN_VOTING_PERIOD = 1 days;

    /// @dev Maximum time durations
    uint256 public constant MAX_DURATION = 365 days;
    uint256 public constant MAX_SUBSCRIPTION_PERIOD = 5 * 365 days; // 5 years
    uint256 public constant MAX_AUCTION_DURATION = 30 days;
    uint256 public constant MAX_VOTING_PERIOD = 30 days;

    /// @dev Grace periods
    uint256 public constant PAYMENT_GRACE_PERIOD = 3 days;
    uint256 public constant AUCTION_EXTENSION_TIME = 10 minutes;
    uint256 public constant MAX_VOTING_PERIOD = 2 days;

    /// @dev Fee limits (in basis points)
    uint256 public constant MAX_PLATFORM_FEE = 1000; // 10%
    uint256 public constant MAX_CREATOR_ROYALTY = 1000; // 10%
    uint256 public constant MAX_TOTAL_FEES = 2500; // 25%
    uint256 public constant DEFAULT_PLATFORM_FEE = 250; // 2.5%
    
    /// @dev String limits
    uint256 public constant MAX_STRING_LENGTH = 256;
    uint256 public constant MAX_HANDLE_LENGTH = 32;
    uint256 public constant MIN_HANDLE_LENGTH = 3;
    uint256 public constant MAX_BIO_LENGTH = 512;
    uint256 public constant MAX_URL_LENGTH = 2048;
    
    /// @dev Numeric limits
    uint256 public constant MAX_SUPPLY = 1e9 * 1e18; // 1 billion tokens
    uint256 public constant MIN_LIQUIDITY = 1000; // Minimum LP tokens
    uint256 public constant MAX_SLIPPAGE = 5000; // 50% max slippage
    
    /// @dev Social constants
    uint256 public constant MAX_FOLLOWERS_PER_QUERY = 1000;
    uint256 public constant MAX_POSTS_PER_QUERY = 100;
    uint256 public constant POST_COOLDOWN = 1 minutes;
    uint256 public constant LIKE_COOLDOWN = 1 seconds;
    
    /// @dev Gaming constants
    uint256 public constant MAX_PLAYERS_PER_TOURNAMENT = 10000;
    uint256 public constant MIN_TOURNAMENT_PRIZE = 0.001 ether;
    uint256 public constant TOURNAMENT_REGISTRATION_PERIOD = 7 days;
    
    /// @dev DeFi constants
    uint256 public constant MIN_COLLATERAL_RATIO = 12000; // 120%
    uint256 public constant LIQUIDATION_THRESHOLD = 11000; // 110%
    uint256 public constant MAX_INTEREST_RATE = 10000; // 100% APY
    uint256 public constant BASE_INTEREST_RATE = 100; // 1% base rate
    
    /// @dev NFT constants
    uint256 public constant MAX_NFT_SUPPLY = 100000;
    uint256 public constant MAX_BATCH_MINT = 100;
    uint256 public constant NFT_REVEAL_DELAY = 7 days;
    
    /// @dev Gas limits
    uint256 public constant MAX_GAS_LIMIT = 1000000;
    uint256 public constant STANDARD_GAS_LIMIT = 200000;
    uint256 public constant SIMPLE_TRANSFER_GAS = 21000;
    
    /// @dev Account abstraction constants
    uint256 public constant USER_OP_VALID_DURATION = 1 hours;
    uint256 public constant MAX_GAS_PRICE = 100 gwei;
    uint256 public constant PAYMASTER_DEPOSIT_MINIMUM = 0.1 ether;
    
    /// @dev Bridge constants
    uint256 public constant MIN_BRIDGE_AMOUNT = 0.001 ether;
    uint256 public constant MAX_BRIDGE_AMOUNT = 1000 ether;
    uint256 public constant BRIDGE_CONFIRMATION_BLOCKS = 12;
    uint256 public constant BRIDGE_TIMEOUT = 1 days;
    
    /// @dev Security constants
    uint256 public constant MAX_SIGNATURE_AGE = 1 hours;
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;
    uint256 public constant MAX_REQUESTS_PER_WINDOW = 100;
    
    /// @dev Error messages (as bytes32 for gas efficiency)
    bytes32 public constant UNAUTHORIZED_ERROR = keccak256("UNAUTHORIZED");
    bytes32 public constant INVALID_AMOUNT_ERROR = keccak256("INVALID_AMOUNT");
    bytes32 public constant INSUFFICIENT_BALANCE_ERROR = keccak256("INSUFFICIENT_BALANCE");
    bytes32 public constant EXPIRED_ERROR = keccak256("EXPIRED");
    bytes32 public constant ALREADY_EXISTS_ERROR = keccak256("ALREADY_EXISTS");
    bytes32 public constant NOT_FOUND_ERROR = keccak256("NOT_FOUND");
    bytes32 public constant PAUSED_ERROR = keccak256("PAUSED");
    bytes32 public constant INVALID_SIGNATURE_ERROR = keccak256("INVALID_SIGNATURE");
    
    /// @dev Special addresses
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    /// @dev Chain IDs
    uint256 public constant ETHEREUM_MAINNET = 1;
    uint256 public constant BASE_MAINNET = 8453;
    uint256 public constant BASE_GOERLI = 84531;
    
    /// @dev EIP-712 Domain
    string public constant EIP712_DOMAIN_NAME = "BaseContracts";
    string public constant EIP712_DOMAIN_VERSION = "1";
    
    /// @dev Role identifiers  
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
}