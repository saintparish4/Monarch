"""Slither detectors for ERC-7562 validation-phase rules."""

from slither.core.declarations import Function
from slither.detectors.abstract_detector import AbstractDetector, DetectorClassification

from .rules import BANNED_CALLS, BANNED_VARIABLES, RULES, VALIDATION_ENTRY_POINTS


def _callee(operation):
    """The Function a call operation targets, or None."""
    target = getattr(operation, "function", None)
    return target if isinstance(target, Function) else None


def _self_call_target(operation):
    """The function a `this.f()` call runs, or None for any other external call.

    Slither resolves the call against the contract being analysed, so a
    `this.f()` written in a base reaches the override the deployed contract
    actually runs. The `SelfCallOverride` fixture pins that.
    """
    if str(getattr(operation, "destination", "")) != "this":
        return None
    return _callee(operation)


def reachable_from(entry):
    """Every function reachable from `entry` during the validation phase.

    Followed: internal calls, modifiers, library calls and `this.f()` calls. The
    bundler's tracer sees every opcode executed under the validation frame,
    whichever of those routes reached it, so the walk has to follow all four.

    Modifiers matter more than they look. A `whenNotPaused` that reads
    `block.timestamp` runs during validation just as surely as the body does,
    and is the easiest place for a banned opcode to hide from a reader.

    Calls to other contracts are not followed: which code sits behind an
    address is a deployment fact, not a source fact.
    """
    seen = {entry}
    queue = [entry]
    while queue:
        current = queue.pop()
        callees = [_callee(op) for op in current.internal_calls]
        callees += list(getattr(current, "modifiers", []))
        callees += [_callee(op) for op in current.library_calls]
        callees += [_self_call_target(op) for _, op in current.high_level_calls]
        for callee in callees:
            if isinstance(callee, Function) and callee not in seen:
                seen.add(callee)
                queue.append(callee)
    return seen


class ValidationPhaseOpcodes(AbstractDetector):
    """Banned opcodes reachable from an ERC-4337 validation entry point."""

    ARGUMENT = "erc7562-validation-opcodes"
    HELP = "Opcodes banned during ERC-4337 validation (ERC-7562)"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.HIGH

    WIKI = "https://eips.ethereum.org/EIPS/eip-7562#opcode-rules"
    WIKI_TITLE = "ERC-7562 forbidden opcode during validation"
    WIKI_DESCRIPTION = (
        "ERC-7562 forbids a set of opcodes during the validation phase of an "
        "ERC-4337 bundle (OP-011), and allows BALANCE and SELFBALANCE only in a "
        "staked entity (OP-080), because their results are not deterministic "
        "across the time between simulation and inclusion. Bundlers enforce this "
        "off-chain, in a tracer, when an operation is submitted. Nothing on-chain "
        "enforces it, so a contract that breaks the rule passes every unit test "
        "and every EntryPoint call in a test VM, then is rejected by every bundler "
        "in production. This is an early check, not a compliance verdict: "
        "ERC-7562's storage, staking and reputation rules are out of its reach."
    )
    WIKI_EXPLOIT_SCENARIO = """
```solidity
function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256)
    external returns (bytes memory context, uint256 validationData)
{
    // TIMESTAMP is banned here. Every operation this paymaster sponsors is
    // dropped by the bundler, and the contract looks correct in every test.
    return ("", _packValidationData(false, uint48(block.timestamp + 1 days), 0));
}
```
The paymaster is deployed, staked and funded, and sponsors nothing."""
    WIKI_RECOMMENDATION = (
        "Move the decision off-chain. For a time range, have the signer commit to "
        "`(validUntil, validAfter)` and return them packed into `validationData` "
        "so the EntryPoint performs the comparison. Validation should decide, "
        "never observe."
    )

    def _detect(self):
        results = []
        # Every concrete contract, not `contracts_derived`. Paymasters are
        # commonly versioned by inheritance — a V8 extending a V7 that is itself
        # deployed and in use — and `contracts_derived` drops every such
        # intermediate, because something inherits it. Reporting the same
        # inherited line once per deployable contract is the honest answer to
        # "will the thing I deploy be rejected".
        for contract in self.compilation_unit.contracts:
            if contract.is_abstract or contract.is_interface or contract.is_library:
                continue
            for entry in contract.functions:
                if entry.name not in VALIDATION_ENTRY_POINTS or not entry.is_implemented:
                    continue
                findings = self._scan(entry)
                for function, node, opcode, spelling in findings:
                    # Name the rule and say why, so the finding is actionable by
                    # someone who has never read ERC-7562: what the bundler does
                    # with this operation, not only which opcode it dislikes.
                    rule, explanation = RULES[opcode]
                    info = [
                        contract.name,
                        ".",
                        entry.name,
                        " reaches ",
                        opcode,
                        f" via `{spelling}`",
                        "" if function is entry else f" in {function.name}",
                        f". ERC-7562 {rule} {explanation}:\n\t- ",
                        node,
                        "\n",
                    ]
                    results.append(self.generate_result(info))
        return results

    @staticmethod
    def _scan(entry):
        """(function, node, opcode, spelling) for every banned use, deduplicated."""
        findings = []
        seen = set()
        for function in sorted(reachable_from(entry), key=lambda f: f.canonical_name):
            for node in function.nodes:
                for variable in node.solidity_variables_read:
                    opcode = BANNED_VARIABLES.get(str(variable))
                    if opcode and (node, str(variable)) not in seen:
                        seen.add((node, str(variable)))
                        findings.append((function, node, opcode, str(variable)))
                for call in node.solidity_calls:
                    # `node.solidity_calls` yields SolidityCall *operations*; the
                    # builtin being called is one level down.
                    builtin = str(getattr(call, "function", call))
                    opcode = BANNED_CALLS.get(builtin)
                    if opcode and (node, builtin) not in seen:
                        seen.add((node, builtin))
                        findings.append((function, node, opcode, builtin))
        return findings
