# forge-attest-example-safe-ops

A reference "producer" repo for [`forge-attest`](../forge-attest). It stands in
for a real operations repo whose Forge scripts build transactions to be submitted
to a Gnosis Safe.

There are two producers, one per JSON shape `forge-attest` verifies:

| Script | Emits | Format |
|--------|-------|--------|
| [`script/BuildSafeTx.s.sol`](script/BuildSafeTx.s.sol) | `out/safe-tx.json` | A complete, flat EIP-712 `SafeTx`. One call, fully specified. |
| [`script/BuildSafeBatch.s.sol`](script/BuildSafeBatch.s.sol) | `out/safe-batch.json` | A Safe{Wallet} **Transaction Builder batch**. Several calls approved as one transaction. |

```bash
forge script script/BuildSafeTx.s.sol:BuildSafeTx        && cat out/safe-tx.json
forge script script/BuildSafeBatch.s.sol:BuildSafeBatch  && cat out/safe-batch.json
```

## The two shapes, and why the difference matters

`BuildSafeTx` emits every EIP-712 `SafeTx` field, so its output *is* a
transaction. Hashing it needs nothing else:

```json
{
  "safe": "0x…", "chainId": "1", "safeVersion": "1.3.0",
  "to": "0x…", "value": "0", "data": "0x…", "operation": "0",
  "safeTxGas": "0", "baseGas": "0", "gasPrice": "0",
  "gasToken": "0x00…00", "refundReceiver": "0x00…00", "nonce": "42"
}
```

`BuildSafeBatch` emits the Transaction Builder format instead. That is the shape
you get from the Safe UI's "export batch", and the one FraxFinance's
[`SafeTxHelper.writeTxs`](https://github.com/FraxFinance/frax-standard-solidity/blob/master/src/SafeTxHelper.sol)
writes:

```json
{
  "version": "1.0",
  "chainId": 1,
  "createdAt": 1760128999000,
  "meta": { "name": "Transactions Batch", "description": "" },
  "transactions": [
    { "to": "0x…", "value": "0", "data": "0x…", "operation": "0" },
    { "to": "0x…", "value": "0", "data": "0x…", "operation": "0" }
  ]
}
```

Note what is *missing*: no Safe address, no nonce, no gas fields. **A batch is not
yet a transaction.** It becomes one only when it is bound to a specific Safe at a
specific nonce and folded into a single `multiSend(bytes)` delegatecall. That is
what the Safe UI does on submission, and what owners actually sign.
`forge-attest` performs that fold from its own config, so the Safe address and
nonce live in the attestation claim rather than in this repo.

Note also `createdAt`. `SafeTxHelper` stamps it with `block.timestamp * 1000`, and
`BuildSafeBatch` copies that behaviour exactly. Under a fork or a broadcast the
value moves every run, so a byte-exact `sha256` of a batch file is not something
you can pin. That is why `forge-attest` also pins a **canonical digest**, computed
after folding and normalisation, which timestamps and formatting cannot move.

## Why this is verifiable

- **Zero dependencies.** The cheatcode interface is declared inline, so there is
  no `forge install`, no `lib/`, and nothing to drift.
- **No hidden inputs.** Every value is a compile-time constant and the JSON is
  built by plain string concatenation. There is no RNG and no on-chain read, so
  the emitted bytes are calldata plus fixed fields and do not depend on the
  compiler.

`BuildSafeTx`'s output is therefore byte-identical on any machine, and
`forge-attest` can pin its `sha256` directly. `BuildSafeBatch`'s output is
byte-identical apart from `createdAt`, and is pinned via the canonical digest.
Either way, a submitted Safe transaction can be proven to be exactly what these
scripts produce, and not something hand-edited on the way to the Safe UI.

The transactions built here are illustrative demo data on Ethereum mainnet against
Safe `0x111CEEee040739fD91D29C34C33E6B3E112F2177`:

- `BuildSafeTx`: `USDC.transfer(0x…dEaD, 1 USDC)`, nonce `42`.
- `BuildSafeBatch`: `USDC.approve(0x1111…0582, 0)` then
  `USDC.transfer(0x…dEaD, 1 USDC)`. A revoke and a transfer that must land
  together or not at all.

## Optional: proposing to the Safe (separate from attestation)

Building the tx and *submitting* it to the Safe are deliberately separate steps.
Submission is exactly where a value could be tampered with, and it is what
`forge-attest` independently checks. This repo includes an optional path that
signs and proposes the built tx to the Safe Transaction Service:

```bash
# 1. build the canonical tx
forge script script/BuildSafeTx.s.sol:BuildSafeTx

# 2. sign the Safe tx hash and emit the Transaction Service payload
PROPOSER_PK=0x<owner-or-delegate-key> forge script script/Propose.s.sol:Propose

# 3. POST it (needs network + a valid proposer)
./propose.sh --network ethereum
```

- `Propose.s.sol` recomputes the EIP-712 Safe tx hash from a canonical SafeTx JSON,
  signs it, and writes `out/proposal.json`, which is the exact POST body including
  `contractTransactionHash`.
- `propose.sh` submits that payload to the network's Transaction Service.

### Proposing a batch

A batch has to be folded and bound first. Reuse `forge-attest`'s normaliser rather
than reimplementing MultiSend packing here. The packing decides what owners sign,
so it should have one implementation on this side and be independently re-derived
by the verifier, not two copies that can drift:

```bash
forge script script/BuildSafeBatch.s.sol:BuildSafeBatch

../forge-attest/lib/normalize.sh --input out/safe-batch.json \
  --safe 0x111CEEee040739fD91D29C34C33E6B3E112F2177 --nonce 43 \
  > out/canonical-safe-tx.json

PROPOSER_PK=0x<key> SAFE_TX_JSON=out/canonical-safe-tx.json \
  forge script script/Propose.s.sol:Propose

./propose.sh --network ethereum --safe-tx out/canonical-safe-tx.json
```

The proposer key must be a Safe **owner or registered delegate**. This path is
**not** part of the attestation or CI pipeline. It only demonstrates the real
submission step that `forge-attest` later verifies against.
