# forge-attest-example-safe-ops

A reference "producer" repo for [`forge-attest`](https://github.com/crossecute/forge-attest/tree/v1.3.0). It stands in
for a real operations repo whose Forge scripts build transactions to be submitted
to a Gnosis Safe.

Five producers cover the original formats and the new readers in v1.3.0:

| Script | Emits | Format |
|--------|-------|--------|
| [`script/BuildSafeTx.s.sol`](script/BuildSafeTx.s.sol) | `out/safe-tx.json` | A complete, flat EIP-712 `SafeTx`. One call, fully specified. |
| [`script/BuildSafeBatch.s.sol`](script/BuildSafeBatch.s.sol) | `out/safe-batch.json` | A Safe{Wallet} **Transaction Builder batch**. Several calls approved as one transaction. |
| [`script/BuildSafeEip712.s.sol`](script/BuildSafeEip712.s.sol) | `out/safe-eip712.json`, `out/safe-eip712-utils.json` | Full EIP-712 envelopes under the `safe` and `safe-utils` profiles. |
| [`script/BuildSafeService.s.sol`](script/BuildSafeService.s.sol) | `out/safe-service.json`, `out/safe-service-utils.json` | Exported proposal requests under both profiles, carrying both hash aliases. |
| [`script/BuildSafeDecodedBatch.s.sol`](script/BuildSafeDecodedBatch.s.sol) | `out/safe-decoded-batch.json` | Decoded method descriptors under `tx-builder` with `static-v1`. |

```bash
forge script script/BuildSafeTx.s.sol:BuildSafeTx        && cat out/safe-tx.json
forge script script/BuildSafeBatch.s.sol:BuildSafeBatch  && cat out/safe-batch.json
forge script script/BuildSafeEip712.s.sol:BuildSafeEip712
forge script script/BuildSafeService.s.sol:BuildSafeService
forge script script/BuildSafeDecodedBatch.s.sol:BuildSafeDecodedBatch
```

## Verify with forge-attest v1.3.0

[`attest.toml`](attest.toml) covers all five scripts and seven claims at a pinned producer commit.
Each `[[run]]` runs one script, `[run.defaults]` sets its normalization options,
and `[[run.claim]]` pins its output hashes, chain, Safe and nonce. The scripts
use constants, so they need no `[run.env]` inputs or dependency setup.

With Foundry, Git, Bash and jq installed, run from this repo:

```bash
git clone https://github.com/crossecute/forge-attest.git ../forge-attest
git -C ../forge-attest checkout --detach 09b0c9b69f1b779ffb5938899775f93d2e423528 # v1.3.0
../forge-attest/attest.sh --config attest.toml
```

The [CI workflow](.github/workflows/attest.yml) pins the action to the same release
commit. Both paths re-run the pinned producer and check the canonical hashes with
cast and Solidity. All claims pin their raw file hash except the original batch,
which leaves that pin blank because `createdAt` changes.

These demo claims leave `safe_network` blank, so verification skips the live queue
check and needs no Safe API key. A passing run verifies the producer output;
it does not prove either demo transaction is queued. To adapt the example, pin
your producer commit, Safe, nonce and reviewed hashes, set `safe_network` on each
claim, and use `--require-live` (or `require-live: true` in CI) to require a match
in the Safe queue. The producer pin is independent of the workflow checkout;
update it deliberately when changing the scripts.

## Exercise the v1.3.0 readers

The new examples use separate nonces so all seven claims can be verified together:

| Output | Nonce | What it exercises |
|--------|-------|-------------------|
| `safe-eip712.json` | 44 | Explicit domain type, ordered `SafeTx` types, domain Safe and chain, and every signed message field. |
| `safe-eip712-utils.json` | 45 | The `safe-utils` opt-in allows the omitted domain type. |
| `safe-service.json` | 46 | All signed fields and Safe address; the claim supplies the chain. Both `contractTransactionHash` and `safeTxHash` must match the derived hash. |
| `safe-service-utils.json` | 47 | The `safe-utils` opt-in allows omitted Safe, gas token and refund receiver. The claim binds the Safe and chain; gas/refund fields remain zero. |
| `safe-decoded-batch.json` | 48 | `static-v1` encodes `transfer(address,uint256)` and `setPolicy(bool,uint8)` from descriptors with null calldata, then folds them into MultiSend. |

The typed-data and service examples each build the same 1 USDC transfer as the
flat example, at their respective nonces. The service producer computes its
carried hashes in Solidity. Verification independently checks them with cast and
Solidity. It exports files only and does not contact the service or sign anything.

The decoded batch uses all four supported scalar types. `setPolicy` targets the
illustrative address `0x2222222222222222222222222222222222222222`; no deployed
policy contract is assumed. Its fixed `createdAt` makes the source byte-stable.
Only the off-chain JSON format changes: equivalent decoded and encoded calls have
the same canonical transaction, on-chain calldata and execution cost. Each static
argument occupies one 32-byte ABI word. See the
[v1.3.0 reader profiles](https://github.com/crossecute/forge-attest/blob/v1.3.0/docs/producer-readers.md)
for schema limits and unsupported inputs.

With the verifier checked out at the pinned release above, run:

```bash
bash test/features.sh ../forge-attest
```

This regenerates all artifacts, compares each typed/service form with a flat
transaction at the same nonce, and compares the decoded batch with independently
encoded calldata. It also checks the `tx-builder-decoded` alias and rejects missing
profile opt-ins, a wrong typed-data chain, a wrong service hash, conflicting
calldata and uint8 overflow. Finally it attests all seven pinned claims using a
local Git clone and checks cast/Solidity agreement. The pinned producer commit
must exist locally. CI runs the same checks in addition to the release action.

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

- **Zero dependencies.** The minimal cheatcode interface and file writer live in
  [`script/SafeExample.sol`](script/SafeExample.sol), so there is
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

The transactions built here are illustrative demo data for Ethereum mainnet against
Safe `0x111CEEee040739fD91D29C34C33E6B3E112F2177`:

- `BuildSafeTx`: `USDC.transfer(0x…dEaD, 1 USDC)`, nonce `42`.
- `BuildSafeBatch`: `USDC.approve(0x1111…0582, 0)` then
  `USDC.transfer(0x…dEaD, 1 USDC)`. A revoke and a transfer that must land
  together or not at all.
- The new typed-data and service outputs repeat the transfer at nonces `44` to
  `47`. The decoded batch at nonce `48` adds the illustrative policy call above.

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
[`forge-attest` v1.3.0 README](https://github.com/crossecute/forge-attest/blob/v1.3.0/README.md#signing-off-from-the-command-line).
