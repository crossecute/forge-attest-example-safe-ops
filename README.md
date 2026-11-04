# forge-attest-example-safe-ops

A reference "producer" repo for [`forge-attest`](https://github.com/crossecute/forge-attest/tree/v1.2.0). It stands in
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

## Verify with forge-attest v1.2.0

[`attest.toml`](attest.toml) covers both scripts at a pinned producer commit.
Each `[[run]]` runs one script, `[run.defaults]` sets its normalization options,
and `[[run.claim]]` pins its output hashes, chain, Safe and nonce. The scripts
use constants, so they need no `[run.env]` inputs or dependency setup.

With Foundry, Git, Bash and jq installed, run from this repo:

```bash
git clone https://github.com/crossecute/forge-attest.git ../forge-attest
git -C ../forge-attest checkout --detach 9d8905bee25689f0346dfd3db2cc4a5cad0ce31f # v1.2.0
../forge-attest/attest.sh --config attest.toml
```

The [CI workflow](.github/workflows/attest.yml) pins the action to the same release
commit. Both paths re-run the pinned producer and check the canonical hashes with
cast and Solidity. The flat transaction also pins its raw file hash. The batch
leaves that pin blank because `createdAt` changes.

These demo claims leave `safe_network` blank, so verification skips the live queue
check and needs no Safe API key. A passing run verifies the producer output;
it does not prove either demo transaction is queued. To adapt the example, pin
your producer commit, Safe, nonce and reviewed hashes, set `safe_network` on each
claim, and use `--require-live` (or `require-live: true` in CI) to require a match
in the Safe queue. The producer pin is independent of the workflow checkout;
update it deliberately when changing the scripts.

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
`forge-attest` performs that fold from its config, so the Safe address and
nonce live in the attestation claim rather than in the batch JSON.

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

## Signing off in the Safe

Signing is done by `forge-attest` itself. After adapting the demo claims for your
own transactions and setting each claim's `safe_network` (for example,
`"ethereum"`), `attest.sh --attest` signs the canonical SafeTx it
checked with the signer's own `cast` wallet and submits it to the Safe Transaction
Service: as the proposal, or as a confirmation if it is already queued:

```bash
SAFE_API_KEY=<key> ../forge-attest/attest.sh --config my-claims.toml --attest -- --ledger
```

Batches need no separate folding step: the claim binds the batch to its Safe and
nonce, and what is signed is the same canonical form the verifier hashed. See
"Signing off from the command line" in the
[`forge-attest` v1.2.0 README](https://github.com/crossecute/forge-attest/blob/v1.2.0/README.md#signing-off-from-the-command-line).
