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
BANNED_VARIABLES = {
    "block.timestamp": "TIMESTAMP",
    "block.number": "NUMBER",
    "block.difficulty": "DIFFICULTY",
    "block.prevrandao": "PREVRANDAO",
    "block.coinbase": "COINBASE",
    "block.gaslimit": "GASLIMIT",
    "block.basefee": "BASEFEE",
    "block.blobbasefee": "BLOBBASEFEE",
    "block.blockhash": "BLOCKHASH",
    "block.prevhash": "BLOCKHASH",
    "tx.origin": "ORIGIN",
    "tx.gasprice": "GASPRICE",
    "self.balance": "SELFBALANCE",
}

# Banned builtins, matched on Slither's SolidityFunction name.
BANNED_CALLS = {
    "blockhash(uint256)": "BLOCKHASH",
    "balance(address)": "BALANCE",
    "selfdestruct(address)": "SELFDESTRUCT",
    "suicide(address)": "SELFDESTRUCT",
    "blobhash(uint256)": "BLOBHASH",
}

# Explicitly permitted, listed so the exclusions are a decision rather than an
# oversight. CHAINID is allowed and is load-bearing: a sponsorship signature
# that does not commit to the chain id is replayable across chains.
PERMITTED = {"block.chainid", "chain.id", "msg.sender", "msg.data", "msg.sig", "msg.value"}

# Deliberately NOT banned here, though ERC-7562 restricts them:
#
#   GAS      — permitted immediately before an external call, and distinguishing
#              that from misuse needs dataflow this detector does not do. Flagging
#              every `gasleft()` would be noise.
#   CREATE   — permitted for the factory deploying the sender. Same problem.
#   External calls to non-sender-associated addresses — the rule is about the
#              *address*, not the call, and resolving that statically needs the
#              storage-association analysis. Worth doing; not in v1.
#
# Each is a real rule and each is listed in the roadmap rather than silently
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
