// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Minimal cheatcode surface, declared inline so this example repo has ZERO
///      dependencies: no forge-std, no `forge install`. That keeps the producer
///      self-contained, and makes its output easy to reproduce.
interface Vm {
    function toString(address value) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
    function toString(bytes calldata value) external pure returns (string memory);
    function projectRoot() external view returns (string memory);
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
}

/// @title BuildSafeTx
/// @notice A stand-in for a "real" ops repo's Forge script. It builds a single
///         Gnosis Safe transaction (an ERC-20 transfer) and writes the full set
///         of EIP-712 SafeTx fields to `out/safe-tx.json`.
///
///         The output must be the same bytes every time. Every input below is a
///         compile-time constant, and the output is assembled by plain string
///         concatenation, so running this script always yields identical JSON.
///         That is what lets `forge-attest` pin a sha256 of the output and catch
///         any tampering.
contract BuildSafeTx {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Pinned transaction inputs. A real script would derive these.
    address internal constant SAFE      = 0x111CEEee040739fD91D29C34C33E6B3E112F2177;
    uint256 internal constant CHAIN_ID  = 1;          // Ethereum mainnet
    string  internal constant VERSION   = "1.3.0";    // Safe contract version (domain uses chainId)
    uint256 internal constant NONCE     = 42;

    // Payload: USDC.transfer(0x…dEaD, 1_000000)  (1 USDC, 6 decimals)
    address internal constant USDC      = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant RECIPIENT = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant AMOUNT    = 1_000000;

    function run() external {
        // Build the inner call the Safe will execute.
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, AMOUNT);

        // Standard SafeTx defaults for a plain call (no delegatecall, no refunds).
        address to             = USDC;
        uint256 value          = 0;
        uint256 operation      = 0; // 0 = CALL, 1 = DELEGATECALL
        uint256 safeTxGas      = 0;
        uint256 baseGas        = 0;
        uint256 gasPrice       = 0;
        address gasToken       = address(0);
        address refundReceiver = address(0);

        // Assemble the canonical JSON by hand, so the bytes are the same on any
        // machine and under any solc. Every scalar is a quoted string, so large
        // integers parse downstream without losing precision.
        string memory json = string.concat(
            "{\n",
            '  "safe": "',           vm.toString(SAFE),            "\",\n",
            '  "chainId": "',        vm.toString(CHAIN_ID),        "\",\n",
            '  "safeVersion": "',    VERSION,                      "\",\n",
            '  "to": "',             vm.toString(to),              "\",\n",
            '  "value": "',          vm.toString(value),           "\",\n",
            '  "data": "',           vm.toString(data),            "\",\n",
            '  "operation": "',      vm.toString(operation),       "\",\n",
            '  "safeTxGas": "',      vm.toString(safeTxGas),       "\",\n",
            '  "baseGas": "',        vm.toString(baseGas),         "\",\n",
            '  "gasPrice": "',       vm.toString(gasPrice),        "\",\n",
            '  "gasToken": "',       vm.toString(gasToken),        "\",\n",
            '  "refundReceiver": "', vm.toString(refundReceiver),  "\",\n",
            '  "nonce": "',          vm.toString(NONCE),           "\"\n",
            "}\n"
        );

        string memory outDir = string.concat(vm.projectRoot(), "/out");
        vm.createDir(outDir, true);
        vm.writeFile(string.concat(outDir, "/safe-tx.json"), json);
    }
}
