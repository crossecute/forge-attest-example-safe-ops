#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$(cd "${1:?usage: bash test/features.sh /path/to/forge-attest}" && pwd)"
RELEASE=09b0c9b69f1b779ffb5938899775f93d2e423528
[[ "$(git -C "$VERIFIER" rev-parse HEAD)" == "$RELEASE" ]] || {
  echo "Expected forge-attest v1.3.0 ($RELEASE)" >&2
  exit 1
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"

for producer in BuildSafeTx BuildSafeBatch BuildSafeEip712 BuildSafeService BuildSafeDecodedBatch; do
  forge script "script/$producer.s.sol:$producer" >"$TMP/forge.log" 2>&1 || {
    cat "$TMP/forge.log" >&2
    exit 1
  }
done

normalize() {
  local input=$1 format=$2 profile=$3 nonce=$4
  bash "$VERIFIER/lib/normalize.sh" --input "$input" --format "$format" --profile "$profile" \
    --safe 0x111CEEee040739fD91D29C34C33E6B3E112F2177 --chain-id 1 --nonce "$nonce"
}

refused() {
  local reason=$1
  shift
  if "$@" >"$TMP/rejected.json" 2>"$TMP/rejected.log"; then
    echo "Expected rejection: $reason" >&2
    exit 1
  fi
  [[ -s "$TMP/rejected.log" ]]
  printf 'PASS: refused %s\n' "$reason"
}

# Different source profiles must preserve every signed field of the flat form.
while read -r name format profile nonce; do
  normalize "out/$name.json" "$format" "$profile" "$nonce" >"$TMP/actual.json"
  jq --arg nonce "$nonce" '.nonce = $nonce' out/safe-tx.json >"$TMP/flat.json"
  normalize "$TMP/flat.json" safe-tx '' "$nonce" >"$TMP/expected.json"
  cmp "$TMP/expected.json" "$TMP/actual.json"
  printf 'PASS: %s equals the flat SafeTx at nonce %s\n' "$name" "$nonce"
done <<'CASES'
safe-eip712 safe-eip712 safe 44
safe-eip712-utils safe-eip712 safe-utils 45
safe-service safe-service safe 46
safe-service-utils safe-service safe-utils 47
CASES

transfer=$(cast calldata 'transfer(address,uint256)' 0x000000000000000000000000000000000000dEaD 1000000)
policy=$(cast calldata 'setPolicy(bool,uint8)' true 255)
jq --arg transfer "$transfer" --arg policy "$policy" '
  .transactions[0].data = $transfer | .transactions[1].data = $policy |
  .transactions |= map(del(.contractMethod, .contractInputsValues))
' out/safe-decoded-batch.json >"$TMP/encoded.json"
normalize out/safe-decoded-batch.json tx-builder static-v1 48 >"$TMP/decoded.json"
normalize "$TMP/encoded.json" tx-builder '' 48 >"$TMP/encoded-canonical.json"
cmp "$TMP/decoded.json" "$TMP/encoded-canonical.json"
normalize out/safe-decoded-batch.json tx-builder-decoded static-v1 48 >"$TMP/alias.json"
cmp "$TMP/decoded.json" "$TMP/alias.json"
printf 'PASS: decoded scalar calls and alias equal encoded MultiSend\n'

refused 'omitted domain type without safe-utils' normalize out/safe-eip712-utils.json safe-eip712 safe 45
refused 'omitted request addresses without safe-utils' normalize out/safe-service-utils.json safe-service safe 47
refused 'decoded calldata without static-v1' normalize out/safe-decoded-batch.json tx-builder '' 48
jq '.domain.chainId = "10"' out/safe-eip712.json >"$TMP/wrong-chain.json"
refused 'typed-data chain mismatch' normalize "$TMP/wrong-chain.json" safe-eip712 safe 44
jq '.safeTxHash = "0x0000000000000000000000000000000000000000000000000000000000000000"' \
  out/safe-service.json >"$TMP/wrong-hash.json"
refused 'mismatched carried service hash' normalize "$TMP/wrong-hash.json" safe-service safe 46
jq '.transactions[0].data = "0x"' out/safe-decoded-batch.json >"$TMP/wrong-data.json"
refused 'descriptor and supplied calldata mismatch' normalize "$TMP/wrong-data.json" tx-builder static-v1 48
jq '.transactions[1].contractInputsValues.level = "256"' out/safe-decoded-batch.json >"$TMP/overflow.json"
refused 'uint8 overflow' normalize "$TMP/overflow.json" tx-builder static-v1 48

# Keep all reviewed pins, replacing only the transport with the local Git repo.
sed "s|^producer_repo = .*|producer_repo = \"file://$ROOT\"|" attest.toml >"$TMP/attest.toml"
bash "$VERIFIER/attest.sh" --config "$TMP/attest.toml" --json >"$TMP/verdict.json"
jq -e '.attested and (.claims | length == 7) and
  all(.claims[]; .attested and (.hashes.safe_tx == .hashes.safe_tx_solidity))' "$TMP/verdict.json" >/dev/null
printf 'PASS: all seven pinned claims attest, including independent Solidity hashes\n'
