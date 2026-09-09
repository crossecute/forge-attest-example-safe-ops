#!/usr/bin/env bash
#
# OPTIONAL: submit the built transaction to the Safe Transaction Service.
#
#   1. Build the tx          : forge script script/BuildSafeTx.s.sol:BuildSafeTx
#   2. Sign + make payload   : PROPOSER_PK=0x... forge script script/Propose.s.sol:Propose
#   3. POST it (this script) : ./propose.sh --network ethereum
#
# For a batch built by BuildSafeBatch, fold it into a canonical SafeTx first (see
# script/Propose.s.sol) and pass that file through:
#
#   SAFE_TX_JSON=out/canonical-safe-tx.json forge script script/Propose.s.sol:Propose
#   ./propose.sh --network ethereum --safe-tx out/canonical-safe-tx.json
#
# The proposer key must belong to a Safe owner or a registered delegate, or the
# service will reject the proposal. Nothing here is part of the attestation path.
set -euo pipefail

NETWORK="ethereum"
PAYLOAD="out/proposal.json"
SAFE_TX="${SAFE_TX_JSON:-out/safe-tx.json}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network) NETWORK="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    --safe-tx) SAFE_TX="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PAYLOAD" ]] || { echo "missing $PAYLOAD: run the Propose script first" >&2; exit 1; }
[[ -f "$SAFE_TX" ]] || { echo "missing $SAFE_TX: pass --safe-tx <canonical SafeTx json>" >&2; exit 1; }

# The Safe address lives in the built tx, not the proposal body.
SAFE=$(jq -r .safe "$SAFE_TX")

# Safe Transaction Service base URLs are per-network, for example
#   ethereum -> https://safe-transaction-mainnet.safe.global
# The common names are mapped below. Add more as needed.
case "$NETWORK" in
  ethereum|mainnet) HOST="safe-transaction-mainnet.safe.global" ;;
  arbitrum)         HOST="safe-transaction-arbitrum.safe.global" ;;
  optimism)         HOST="safe-transaction-optimism.safe.global" ;;
  base)             HOST="safe-transaction-base.safe.global" ;;
  polygon)          HOST="safe-transaction-polygon.safe.global" ;;
  gnosis)           HOST="safe-transaction-gnosis-chain.safe.global" ;;
  sepolia)          HOST="safe-transaction-sepolia.safe.global" ;;
  *) echo "unknown network '$NETWORK': add its Transaction Service host to propose.sh" >&2; exit 1 ;;
esac

URL="https://${HOST}/api/v1/safes/${SAFE}/multisig-transactions/"
echo "POST $URL"
curl -fsSL -X POST "$URL" \
  -H 'content-type: application/json' \
  --data-binary @"$PAYLOAD" \
  && echo "  -> proposed"
