# Walkthrough: a zero-ETH wallet, sponsored on Base Sepolia

This takes you from a fresh clone to a wallet that has never held ETH sending a
transaction on Base Sepolia, paid for by a paymaster you deployed. It is the
demo in [`demo/`](../demo), run end to end against your own deployment, and
then undone so you get your testnet ETH back.

> **Base Sepolia only.** Monarch is not audited. The deploy scripts refuse any
> chain but Base Sepolia and a local anvil, and the demo's sponsor route signs
> for anyone who asks. Use keys that have never held mainnet funds and never
> will.

You will need about 0.02 Base Sepolia ETH, and about half an hour.

## 0. What you need

- [Foundry](https://getfoundry.sh) (the repository's CI pins v1.8.1)
- Node.js 24 and npm
- The repository with its submodules:

```bash
git clone --recurse-submodules https://github.com/saintparish4/monarch
cd monarch
forge build
```

## 1. Two keys

The paymaster needs an owner, which pays for the deployment, and the app needs
a signer, which approves sponsorships and never holds anything.

```bash
cast wallet new    # the deployer: owns the paymaster, and is the demo app
cast wallet new    # the app signer: signs sponsorships, never funded
cp .env.example .env
```

Put the two private keys in `.env` as `DEPLOYER_PRIVATE_KEY` and
`APP_SIGNER_PRIVATE_KEY`. `.env` is git-ignored, and `forge` reads it
automatically. Load it into your shell for the `cast` commands below:

```bash
set -a; . ./.env; set +a
DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
APP_SIGNER=$(cast wallet address --private-key "$APP_SIGNER_PRIVATE_KEY")
```

## 2. Fund the deployer

Get about 0.02 ETH on Base Sepolia into `$DEPLOYER` from any Base Sepolia
faucet. That covers everything the scripts spend by default:

| What                | Default   | Comes back?                               |
| ------------------- | --------- | ----------------------------------------- |
| Stake               | 0.01 ETH  | Yes, one day after you unlock it (step 7) |
| Owner buffer        | 0.001 ETH | Yes, whatever operations have not used    |
| App budget          | 0.005 ETH | Yes, whatever operations have not used    |
| Gas for the scripts | small     | No                                        |

```bash
cast balance "$DEPLOYER" --rpc-url base_sepolia --ether
```

The public RPC can lag a few blocks behind. If a balance looks wrong straight
after a transaction, wait a minute and read it again.

## 3. Deploy, stake and fund the buffer

One broadcast deploys the paymaster, stakes it, and deposits the owner buffer.
It is one broadcast on purpose: an unstaked paymaster looks deployed and
sponsors nothing, because bundlers reject a paymaster that reads storage the
sender does not own unless it is staked.

```bash
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast
```

It prints `MonarchPaymaster 0x…`. Keep that address:

```bash
PAYMASTER=0x…
```

## 4. Register the app and fund its budget

```bash
PAYMASTER=$PAYMASTER APP_SIGNER=$APP_SIGNER \
  forge script script/RegisterApp.s.sol --rpc-url base_sepolia --broadcast
```

The app is the deployer's address unless you set `APP`. Check what the
paymaster now believes:

```bash
ENTRYPOINT=0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108

# (budget in wei, signer): the signer must be $APP_SIGNER
cast call "$PAYMASTER" "apps(address)(uint96,address)" "$DEPLOYER" --rpc-url base_sepolia

# (deposit, staked, stake, unstakeDelaySec, withdrawTime): staked must be true
cast call "$ENTRYPOINT" "getDepositInfo(address)((uint256,bool,uint112,uint32,uint48))" \
  "$PAYMASTER" --rpc-url base_sepolia
```

## 5. Run the demo against your paymaster

The demo reads the live deployment's addresses from
[`deployments/base-sepolia.json`](../deployments/base-sepolia.json). Point it at
yours instead with two environment variables, and it takes the signer key from
the repository's `.env`:

```bash
cd demo
npm install
NEXT_PUBLIC_PAYMASTER=$PAYMASTER NEXT_PUBLIC_APP=$DEPLOYER npm run dev
```

Open <http://localhost:3000>. The page generates an owner key in your browser
and derives a `SimpleAccount` from it; both show 0 ETH. Press **Send a
sponsored transaction**.

What happens:

1. The page builds an operation and asks the demo's server route,
   `demo/app/api/sponsor/route.ts`, for a stub sponsorship so the bundler can
   estimate gas.
2. With the estimate in hand it asks again. The route asks your paymaster for
   the digest to sign (`getSponsorshipHash`, over `eth_call`), checks the app's
   budget covers the worst case, and signs as the app.
3. The page signs the operation as the account owner and sends it to the public
   bundler.
4. The bundler includes it. The first operation also deploys the account.

The page shows the transaction and what the app was charged, read from the
paymaster's `SponsorshipCharged` event. The owner key and the account still
hold 0 ETH. On the live deployment the first operation cost the app about
0.0000017 ETH and a repeat about 0.0000009 ETH.

## 6. If it fails

The page shows the bundler's error unedited, because when a bundler rejects an
operation that string is the only record of why.

| You see                                                 | It means                                                                               |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `server has no APP_SIGNER_PRIVATE_KEY`                  | The route found no signer key. It reads `APP_SIGNER_PRIVATE_KEY` from the root `.env`. |
| `this server signs as 0x…, but the app's signer is 0x…` | The key in `.env` is not the one you registered in step 4.                             |
| `app budget … cannot cover …`                           | Fund the app again: re-run step 4's script with `APP_BUDGET_WEI`, or call `fundApp`.   |
| `AA31 paymaster deposit too low`                        | The paymaster's EntryPoint deposit cannot cover the operation's worst case.            |
| `AA33 reverted …`                                       | The paymaster's validation reverted. The data after it names the reason.               |
| `AA34 signature error`                                  | The app's signature did not recover to the registered signer.                          |
| A rejection that mentions stake or reputation           | The bundler wants more stake. `addStake` is additive, so top it up.                    |

[`cases/`](../cases) has the long form of several of these: why a paymaster
that works in its tests is rejected by a bundler, reproduced against the real
EntryPoint.

## 7. Get the ETH back

Everything but the gas is recoverable. The app withdraws its budget, the owner
withdraws what is left of the buffer, and the stake comes back a day after it
is unlocked. These are the same calls that recovered the three retired
paymasters recorded in `deployments/base-sepolia.json`.

```bash
# The app's unspent budget (the app is the deployer here).
BUDGET=$(cast call "$PAYMASTER" "apps(address)(uint96,address)" "$DEPLOYER" \
  --rpc-url base_sepolia | head -1 | cut -d' ' -f1)
cast send "$PAYMASTER" "withdrawAppBudget(address,uint256)" "$DEPLOYER" "$BUDGET" \
  --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url base_sepolia

# The owner's buffer: only the free balance, never an app's or a user's money.
FREE=$(cast call "$PAYMASTER" "freeBalance()(uint256)" --rpc-url base_sepolia | cut -d' ' -f1)
cast send "$PAYMASTER" "withdrawTo(address,uint256)" "$DEPLOYER" "$FREE" \
  --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url base_sepolia

# The stake: unlock now, withdraw after the one-day delay.
cast send "$PAYMASTER" "unlockStake()" \
  --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url base_sepolia
# ...a day later:
cast send "$PAYMASTER" "withdrawStake(address)" "$DEPLOYER" \
  --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url base_sepolia
```

Once the stake is unlocked the paymaster stops serving sponsored operations,
until it stakes again.
