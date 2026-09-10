# Monarch demo — a wallet with no ETH writes to a contract

A browser generates a fresh key, funds it with nothing, and uses it to sign a
guestbook on Base Sepolia. The app's budget on the paymaster pays the gas. The
transaction shows up on Basescan like any other.

This is the shortest honest demonstration of what the paymaster is for: a user
who has never held a token does something on-chain, and does not first have to
go and buy ETH.

## What is actually happening

```
browser                       sponsor api                    chain
  |                                |                            |
  | 1. build the call              |                            |
  |------------------------------->|                            |
  |    (bundler estimates gas)     |                            |
  |                                |                            |
  | 2. POST /api/sponsor           |                            |
  |------------------------------->|                            |
  |                                | 3. getSponsorshipHash()    |
  |                                |--------------------------->|
  |                                |<---------------------------|
  |                                | 4. sign it with the app    |
  |                                |    signer key              |
  |<-------------------------------|                            |
  |    paymasterData (98 bytes)    |                            |
  |                                |                            |
  | 5. the account owner signs the whole operation              |
  | 6. send to the bundler --------------------------------->   |
  |                                                             |
  |                     EntryPoint -> validatePaymasterUserOp    |
  |                     execute    -> Guestbook.sign()           |
  |                     postOp     -> charge the app's budget    |
```

**The ordering in steps 4 and 5 is the part that is easy to get backwards.**
The sponsorship digest covers the final gas values, so it cannot be produced
before the bundler has estimated them — but it must be produced *before* the
account owner signs, because `getSponsorshipHash` deliberately does not cover
`userOp.signature`, while the account's signature does cover
`paymasterAndData`. Sponsor first, then sign. Doing it the other way gets an
AA24 from the account and no useful error message.

**Two processes, on purpose.** The app signer key authorises spending the app's
entire budget. It lives in the server process and never reaches the browser. A
demo that signed in the browser would be a demo of how to lose your budget.

## Run it

You need a deployed paymaster (see [`script/Deploy.s.sol`](../script/Deploy.s.sol))
and any ERC-4337 **v0.8** bundler endpoint for Base Sepolia.

```bash
cp .env.example .env      # fill in the addresses the deploy script printed
npm install
npm run dev               # sponsor api on :8787, web app on :5173
```

`npm run dev` runs both processes. The Vite dev server proxies `/api` to the
sponsor, so the browser only ever talks to one origin.

## Layout

```
shared/     byte layout shared by both processes, plus its tests
server/     the sponsor: policy, signing, one eth_call
src/        the page
```

`shared/monarch.ts` and `contracts/libraries/Constants.sol` are two copies of
one byte layout in two languages, and nothing makes them agree automatically.
So `shared/monarch.test.ts` **parses the offsets out of the Solidity source** at
test time and asserts the TypeScript matches. Drift there does not crash — it
decodes a plausible, wrong app address — which is the same class of bug the
decoder rewrite in this repo's history exists to remove.

```bash
npm test          # 5 tests: offsets, lengths, field positions, pack order
npm run build     # typecheck, tests, then bundle
```

## Things this demo is not

- **Not a production sponsor policy.** `shouldSponsor` in `server/index.ts`
  accepts any call to the guestbook. A real app checks who the user is and
  what they have spent. That function is where your rules go, and it is the
  only thing standing between a stranger and your budget.
- **Not account-abstraction-wallet advice.** The burner key sits in
  `localStorage` because it is worth exactly zero. Do not copy that.
- **Not audited.** Neither is the paymaster.
