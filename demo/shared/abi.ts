/**
 * Only the fragments the demo actually calls. Hand-written rather than
 * generated from `out/` so the demo builds without a Foundry artifact tree.
 */
export const paymasterAbi = [
  {
    type: 'function',
    name: 'getSponsorshipHash',
    stateMutability: 'view',
    inputs: [
      {
        name: 'userOp',
        type: 'tuple',
        components: [
          {name: 'sender', type: 'address'},
          {name: 'nonce', type: 'uint256'},
          {name: 'initCode', type: 'bytes'},
          {name: 'callData', type: 'bytes'},
          {name: 'accountGasLimits', type: 'bytes32'},
          {name: 'preVerificationGas', type: 'uint256'},
          {name: 'gasFees', type: 'bytes32'},
          {name: 'paymasterAndData', type: 'bytes'},
          {name: 'signature', type: 'bytes'},
        ],
      },
    ],
    outputs: [{name: '', type: 'bytes32'}],
  },
  {
    type: 'function',
    name: 'apps',
    stateMutability: 'view',
    inputs: [{name: '', type: 'address'}],
    outputs: [
      {name: 'budget', type: 'uint96'},
      {name: 'signer', type: 'address'},
    ],
  },
  {
    type: 'function',
    name: 'freeBalance',
    stateMutability: 'view',
    inputs: [],
    outputs: [{name: '', type: 'uint256'}],
  },
] as const

export const guestbookAbi = [
  {
    type: 'function',
    name: 'sign',
    stateMutability: 'nonpayable',
    inputs: [{name: 'message', type: 'string'}],
    outputs: [],
  },
  {
    type: 'function',
    name: 'count',
    stateMutability: 'view',
    inputs: [],
    outputs: [{name: '', type: 'uint256'}],
  },
  {
    type: 'function',
    name: 'latest',
    stateMutability: 'view',
    inputs: [{name: 'n', type: 'uint256'}],
    outputs: [
      {
        name: 'out',
        type: 'tuple[]',
        components: [
          {name: 'author', type: 'address'},
          {name: 'timestamp', type: 'uint64'},
          {name: 'message', type: 'string'},
        ],
      },
    ],
  },
] as const
