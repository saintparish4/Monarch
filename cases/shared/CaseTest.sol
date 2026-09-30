// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "account-abstraction/accounts/SimpleAccount.sol";
import {SimpleAccountFactory} from "account-abstraction/accounts/SimpleAccountFactory.sol";

/// @notice Something for a sponsored operation to do, so a test can see it ran.
contract Target {
    mapping(address caller => string note) public lastNote;

    function note(string calldata text) external {
        lastNote[msg.sender] = text;
    }
}

/// @title CaseTest
/// @notice The harness every case runs on: the real EntryPoint v0.8, real
///         `SimpleAccount`s from the real factory, and `handleOps` called the
///         way a bundler calls it.
/// @dev No mocks. A mocked EntryPoint agrees with whatever its author believes,
///      and every case in this directory is a belief that turned out wrong.
///
///      What the harness cannot give you is a bundler. The EntryPoint enforces
///      nothing from ERC-7562 on chain, so `_bannedOpcodeInValidation` stands in
///      for the part of a bundler's tracer that the opcode rules need. It is a
///      small subset of what a bundler checks, and says so.
abstract contract CaseTest is Test {
    uint128 internal constant VERIFICATION_GAS = 150_000;
    uint128 internal constant CALL_GAS = 100_000;
    uint128 internal constant PAYMASTER_VERIFICATION_GAS = 100_000;
    uint128 internal constant PAYMASTER_POSTOP_GAS = 40_000;
    uint256 internal constant PRE_VERIFICATION_GAS = 50_000;
    uint128 internal constant FEE = 1 gwei;

    EntryPoint internal entryPoint;
    SimpleAccountFactory internal factory;
    Target internal target;
    address payable internal bundler = payable(makeAddr("bundler"));

    function setUp() public virtual {
        entryPoint = new EntryPoint();
        factory = new SimpleAccountFactory(IEntryPoint(address(entryPoint)));
        target = new Target();
    }

    // ------------------------------------------------------------ accounts

    /// @dev A deployed account with no ETH. v0.8 gates `createAccount` behind
    ///      the EntryPoint's SenderCreator, so deploying one outside an
    ///      operation means impersonating it.
    function _newAccount(string memory name)
        internal
        returns (SimpleAccount account, uint256 ownerKey)
    {
        (, ownerKey) = makeAddrAndKey(name);
        vm.prank(address(entryPoint.senderCreator()));
        account = factory.createAccount(vm.addr(ownerKey), 0);
    }

    // ------------------------------------------------------------ operations

    /// @dev An operation that calls `target.note(text)` from `account`, with no
    ///      paymaster and no signature yet.
    function _op(SimpleAccount account, string memory text)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op.sender = address(account);
        op.nonce = entryPoint.getNonce(address(account), 0);
        op.callData = abi.encodeCall(
            BaseAccount.execute, (address(target), 0, abi.encodeCall(Target.note, (text)))
        );
        op.accountGasLimits = _pack(VERIFICATION_GAS, CALL_GAS);
        op.preVerificationGas = PRE_VERIFICATION_GAS;
        op.gasFees = _pack(FEE, FEE);
    }

    /// @dev `paymasterAndData` in the v0.7/v0.8 layout: address, verification
    ///      gas limit, postOp gas limit, then the paymaster's own data.
    function _paymasterAndData(address paymaster, uint128 postOpGasLimit, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(paymaster, PAYMASTER_VERIFICATION_GAS, postOpGasLimit, data);
    }

    /// @dev The account owner's signature over the finished operation. Call it
    ///      last: it covers `paymasterAndData`.
    function _signAsAccount(PackedUserOperation memory op, uint256 ownerKey)
        internal
        view
        returns (PackedUserOperation memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, entryPoint.getUserOpHash(op));
        op.signature = abi.encodePacked(r, s, v);
        return op;
    }

    function _handle(PackedUserOperation memory op) internal {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, bundler);
    }

    function _handle(PackedUserOperation[] memory ops) internal {
        entryPoint.handleOps(ops, bundler);
    }

    /// @dev The `maxCost` the EntryPoint passes to `validatePaymasterUserOp`:
    ///      every gas limit in the operation, at its maximum fee.
    function _maxCost(PackedUserOperation memory op) internal pure returns (uint256) {
        uint256 limits = uint128(uint256(op.accountGasLimits >> 128))
            + uint128(uint256(op.accountGasLimits)) + op.preVerificationGas
            + uint128(bytes16(_slice(op.paymasterAndData, 20, 36)))
            + uint128(bytes16(_slice(op.paymasterAndData, 36, 52)));
        return limits * uint128(uint256(op.gasFees));
    }

    // ------------------------------------------------------------ the tracer

    /// @notice Runs the paymaster's validation the way a bundler simulates it,
    ///         and returns the first opcode ERC-7562 forbids there, or zero.
    /// @dev Checks the environment opcodes in OP-011, plus BALANCE and
    ///      SELFBALANCE, which OP-080 allows only for a staked entity. It does
    ///      not check storage access, the GAS rule, calls into the EntryPoint,
    ///      calls to addresses without code, or reputation. A zero here means
    ///      "none of these opcodes ran", not "a bundler will accept this".
    function _bannedOpcodeInValidation(
        IPaymaster paymaster,
        PackedUserOperation memory op,
        bool staked
    ) internal returns (uint8) {
        bytes32 userOpHash = entryPoint.getUserOpHash(op);
        uint256 maxCost = _maxCost(op);

        vm.startDebugTraceRecording();
        vm.prank(address(entryPoint));
        (bool ok,) = address(paymaster)
            .call(abi.encodeCall(IPaymaster.validatePaymasterUserOp, (op, userOpHash, maxCost)));
        Vm.DebugStep[] memory steps = vm.stopAndReturnDebugTraceRecording();
        ok; // a reverting validation still ran its opcodes, and those count

        for (uint256 i = 0; i < steps.length; i++) {
            // Everything this test contract and the cheatcodes did is outside
            // the validation frame.
            address where = steps[i].contractAddr;
            if (where == address(this) || where == address(vm)) continue;
            uint8 opcode = steps[i].opcode;
            if (_isEnvironmentOpcode(opcode)) return opcode;
            if (!staked && (opcode == 0x31 || opcode == 0x47)) return opcode;
        }
        return 0;
    }

    /// @dev OP-011, as ERC-7562 lists it: ORIGIN, GASPRICE, BLOCKHASH,
    ///      COINBASE, TIMESTAMP, NUMBER, PREVRANDAO, GASLIMIT, BASEFEE, BLOBHASH,
    ///      BLOBBASEFEE, CREATE, INVALID, SELFDESTRUCT. CREATE is allowed only
    ///      to deploy the sender, which a paymaster never does.
    function _isEnvironmentOpcode(uint8 opcode) internal pure returns (bool) {
        return opcode == 0x32 || opcode == 0x3A || (opcode >= 0x40 && opcode <= 0x45)
            || opcode == 0x48 || opcode == 0x49 || opcode == 0x4A || opcode == 0xF0
            || opcode == 0xFE || opcode == 0xFF;
    }

    // ------------------------------------------------------------ helpers

    function _pack(uint128 high, uint128 low) internal pure returns (bytes32) {
        return bytes32((uint256(high) << 128) | uint256(low));
    }

    function _slice(bytes memory data, uint256 start, uint256 end)
        internal
        pure
        returns (bytes memory out)
    {
        out = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            out[i - start] = data[i];
        }
    }

    function _depositOf(address paymaster) internal view returns (uint256) {
        return entryPoint.balanceOf(paymaster);
    }
}
