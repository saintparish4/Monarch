"""The ERC-7562 forbidden-opcode set, as it appears in Solidity source.

ERC-7562 restricts what an account, paymaster or factory may execute during the
validation phase of an ERC-4337 bundle. Bundlers enforce it off-chain, in a
tracer, at the moment an operation is submitted. Nothing on-chain enforces it:
a contract that breaks these rules passes every unit test, passes an EntryPoint
call in a test VM, and is then silently rejected by every bundler in production.

That is the gap this plugin exists to close, and the reason a static check is
worth having even though a dynamic one already exists — the dynamic one only
tells you after you have deployed.
"""

# Solidity spellings of banned opcodes, mapped to the opcode they compile to.
# Keys match `str()` of Slither's SolidityVariableComposed.
#
# Every key here must be one some source can actually produce: the test suite
# fails if any key never fires on a fixture. A mapping that claims coverage it
# cannot deliver is the same "says clean, isn't" failure this plugin exists to
# catch, only in the plugin itself.
BANNED_VARIABLES = {
    "block.timestamp": "TIMESTAMP",
    "block.number": "NUMBER",
    "block.difficulty": "DIFFICULTY",
    "block.prevrandao": "PREVRANDAO",
    "block.coinbase": "COINBASE",
    "block.gaslimit": "GASLIMIT",
    "block.basefee": "BASEFEE",
    "block.blobbasefee": "BLOBBASEFEE",
    "tx.origin": "ORIGIN",
    "tx.gasprice": "GASPRICE",
}

# Banned builtins, matched on Slither's SolidityFunction name. Both the Solidity
# builtins and the Yul ones: Slither parses inline assembly into the same nodes
# and names each Yul builtin after itself, with every argument typed uint256.
# Without the Yul half, `assembly { t := timestamp() }` passes clean.
BANNED_CALLS = {
    # Solidity
    "blockhash(uint256)": "BLOCKHASH",
    "blobhash(uint256)": "BLOBHASH",
    "balance(address)": "BALANCE",
    "selfdestruct(address)": "SELFDESTRUCT",
    # Yul. `blockhash` and `blobhash` share their Solidity spelling. Slither
    # rewrites `origin()` to `tx.origin` and `selfbalance()` to
    # `address(this).balance`, so both arrive through the Solidity keys and have
    # none of their own. There is no `difficulty()`: solc rejects it for every
    # EVM version from Paris on, and opcode 0x44 is reached through
    # `prevrandao()` instead.
    "timestamp()": "TIMESTAMP",
    "number()": "NUMBER",
    "prevrandao()": "PREVRANDAO",
    "coinbase()": "COINBASE",
    "gaslimit()": "GASLIMIT",
    "basefee()": "BASEFEE",
    "blobbasefee()": "BLOBBASEFEE",
    "gasprice()": "GASPRICE",
    "balance(uint256)": "BALANCE",
    "selfdestruct(uint256)": "SELFDESTRUCT",
    # Yul only. Solidity's `assert` compiles to a Panic revert, not to INVALID.
    "invalid()": "INVALID",
}

# The ERC-7562 rule behind each opcode above, and what a contract author needs
# to know about it. Rule identifiers are copied from the text of ERC-7562, not
# from memory: https://eips.ethereum.org/EIPS/eip-7562#opcode-rules
#
# The explanation is the part a finding exists to deliver. "Banned opcode" tells
# an author what to delete; "the bundler cannot trust its own simulation" tells
# them why the contract that passed every test is being dropped.
_ENVIRONMENT = (
    "OP-011",
    "forbids it during validation. Its value can change between the bundler's "
    "simulation and the block that includes the operation, so a bundler drops any "
    "operation whose validation uses it",
)
_HALTING = (
    "OP-011",
    "forbids it during validation. A bundler drops any operation whose validation "
    "executes it",
)
RULES = {
    "TIMESTAMP": _ENVIRONMENT,
    "NUMBER": _ENVIRONMENT,
    "DIFFICULTY": _ENVIRONMENT,
    "PREVRANDAO": _ENVIRONMENT,
    "COINBASE": _ENVIRONMENT,
    "GASLIMIT": _ENVIRONMENT,
    "BASEFEE": _ENVIRONMENT,
    "BLOBBASEFEE": _ENVIRONMENT,
    "BLOCKHASH": _ENVIRONMENT,
    "BLOBHASH": _ENVIRONMENT,
    "ORIGIN": _ENVIRONMENT,
    "GASPRICE": _ENVIRONMENT,
    "SELFDESTRUCT": _HALTING,
    "INVALID": _HALTING,
    # The one rule with an exception this detector cannot see: OP-080 allows
    # BALANCE and SELFBALANCE in a staked entity, and whether a contract is
    # staked is a deployment fact, not a source fact. The finding says so.
    "BALANCE": (
        "OP-080",
        "allows it only in a staked entity. Unstaked, a bundler drops the "
        "operation; if this contract is staked, this finding does not apply",
    ),
}

# Explicitly permitted, listed so the exclusions are a decision rather than an
# oversight. The test suite reads every one of these in a clean fixture and
# fails if any is reported. CHAINID is allowed and is load-bearing: a
# sponsorship signature that does not commit to the chain id is replayable
# across chains.
PERMITTED = {
    "block.chainid",
    "chainid()",
    "msg.sender",
    "msg.data",
    "msg.sig",
    "msg.value",
}

# Deliberately NOT banned here, though ERC-7562 restricts them:
#
#   GAS      — OP-012 permits it immediately before a *CALL, and distinguishing
#              that from misuse needs dataflow this detector does not do.
#              Flagging every `gasleft()` would be noise.
#   CREATE   — OP-011 lists it, with exceptions (OP-031, OP-032, EREP-060) for
#              deploying the sender. Same problem.
#   Calls to addresses without code (OP-041), into the EntryPoint (OP-051 to
#   OP-055), and with value (OP-061) — the rules are about the *address* and the
#   deployment, not the source, and need the storage-association analysis.
#
# Each is a real rule and each is listed in the README rather than silently
# skipped, because a checker that quietly ignores a rule is worse than one that
# says which rules it covers.

# Function names that begin the validation phase. Matched by name rather than by
# interface, on purpose: the implementation this plugin was written against
# declared its own `IPaymaster` with the wrong argument list, so an
# interface-based match would have skipped the very contract that motivated it.
VALIDATION_ENTRY_POINTS = {
    "validatePaymasterUserOp",
    "validateUserOp",
}
