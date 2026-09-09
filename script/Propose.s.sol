// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Cheatcode surface needed to read the built tx, sign the Safe tx hash,
///      and serialise a Safe Transaction Service proposal payload. Declared
///      inline to keep this repo dependency-free.
interface Vm {
    function projectRoot() external view returns (string memory);
    function readFile(string calldata path) external view returns (string memory);
    function writeFile(string calldata path, string calldata data) external;
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);
    function parseJsonUint(string calldata json, string calldata key) external pure returns (uint256);
    function parseJsonBytes(string calldata json, string calldata key) external pure returns (bytes memory);
    function envUint(string calldata name) external view returns (uint256);
    function envOr(string calldata name, string calldata defaultValue) external view returns (string memory);
    function addr(uint256 privateKey) external pure returns (address);
    function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
    function toString(address value) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
    function toString(bytes32 value) external pure returns (string memory);
    function toString(bytes calldata value) external pure returns (string memory);
}

/// @title Propose
/// @notice OPTIONAL companion to the producers. Reads a **canonical SafeTx JSON**,
///         recomputes the EIP-712 Safe transaction hash, signs it with a proposer
///         key, and writes `out/proposal.json`. That file is the exact body to
///         POST to the Safe Transaction Service. `propose.sh` does the POST,
///         because Foundry cannot do it cleanly.
///
///         Requires:  PROPOSER_PK  (env, hex private key of a Safe owner/delegate)
///         Optional:  SAFE_TX_JSON (env, path relative to the project root;
///                                  default `out/safe-tx.json`)
///         Run with:  forge script script/Propose.s.sol:Propose
///
///         `BuildSafeTx` writes a canonical SafeTx directly. `BuildSafeBatch`
///         writes a Transaction Builder batch, which is not yet a transaction.
///         Fold it into a canonical SafeTx first, binding it to a Safe and nonce:
///
///           ../forge-attest/lib/normalize.sh --input out/safe-batch.json \
///             --safe 0x<safe> --nonce <n> > out/canonical-safe-tx.json
///           SAFE_TX_JSON=out/canonical-safe-tx.json forge script script/Propose.s.sol:Propose
///
///         Folding lives in `forge-attest` rather than being reimplemented here,
///         on purpose. The MultiSend packing decides what owners sign, so it
///         should have exactly one implementation on the producing side, and it
///         should be the one the verifier independently re-derives.
///
///         This step needs a real Safe, a real proposer key, and a network to be
///         useful. It is NOT part of the attestation or CI path.
contract Propose {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Safe 1.3.0 type hashes (domain binds chainId + verifyingContract).
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 internal constant SAFE_TX_TYPEHASH = keccak256(
        "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    );

    struct SafeTx {
        address safe;
        uint256 chainId;
        address to;
        uint256 value;
        bytes data;
        uint256 operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address refundReceiver;
        uint256 nonce;
    }

    function run() external {
        string memory path = vm.envOr("SAFE_TX_JSON", string("out/safe-tx.json"));
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/", path));

        SafeTx memory t = SafeTx({
            safe: vm.parseJsonAddress(json, ".safe"),
            chainId: vm.parseJsonUint(json, ".chainId"),
            to: vm.parseJsonAddress(json, ".to"),
            value: vm.parseJsonUint(json, ".value"),
            data: vm.parseJsonBytes(json, ".data"),
            operation: vm.parseJsonUint(json, ".operation"),
            safeTxGas: vm.parseJsonUint(json, ".safeTxGas"),
            baseGas: vm.parseJsonUint(json, ".baseGas"),
            gasPrice: vm.parseJsonUint(json, ".gasPrice"),
            gasToken: vm.parseJsonAddress(json, ".gasToken"),
            refundReceiver: vm.parseJsonAddress(json, ".refundReceiver"),
            nonce: vm.parseJsonUint(json, ".nonce")
        });

        bytes32 safeTxHash = _safeTxHash(t);

        // Sign the Safe tx hash with the proposer key (must be an owner/delegate).
        uint256 pk = vm.envUint("PROPOSER_PK");
        address sender = vm.addr(pk);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, safeTxHash);
        bytes memory signature = abi.encodePacked(r, s, v); // the Safe and Ethereum layout

        // Safe Transaction Service POST body. `operation` and `nonce` are
        // numbers. The value and gas fields are strings. Hashes, the signature,
        // and addresses are hex strings.
        string memory origin = vm.envOr("PROPOSAL_ORIGIN", string("forge-attest-example"));
        string memory payload = string.concat(
            "{\n",
            '  "to": "',                     vm.toString(t.to),             "\",\n",
            '  "value": "',                  vm.toString(t.value),          "\",\n",
            '  "data": "',                   vm.toString(t.data),           "\",\n",
            '  "operation": ',               vm.toString(t.operation),      ",\n",
            '  "safeTxGas": "',              vm.toString(t.safeTxGas),      "\",\n",
            '  "baseGas": "',                vm.toString(t.baseGas),        "\",\n",
            '  "gasPrice": "',               vm.toString(t.gasPrice),       "\",\n",
            '  "gasToken": "',               vm.toString(t.gasToken),       "\",\n",
            '  "refundReceiver": "',         vm.toString(t.refundReceiver), "\",\n",
            '  "nonce": ',                   vm.toString(t.nonce),          ",\n",
            '  "contractTransactionHash": "',vm.toString(safeTxHash),       "\",\n",
            '  "sender": "',                 vm.toString(sender),           "\",\n",
            '  "signature": "',              vm.toString(signature),        "\",\n",
            '  "origin": "',                 origin,                        "\"\n",
            "}\n"
        );

        vm.writeFile(string.concat(vm.projectRoot(), "/out/proposal.json"), payload);
    }

    function _safeTxHash(SafeTx memory t) internal pure returns (bytes32) {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, t.chainId, t.safe));
        bytes32 structHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                t.to,
                t.value,
                keccak256(t.data),
                uint8(t.operation),
                t.safeTxGas,
                t.baseGas,
                t.gasPrice,
                t.gasToken,
                t.refundReceiver,
                t.nonce
            )
        );
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, structHash));
    }
}
