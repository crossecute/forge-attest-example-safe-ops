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

/// @title BuildSafeBatch
/// @notice A producer for the *batch* case: several calls that owners approve as
///         one Safe transaction. It emits the Safe{Wallet} Transaction Builder
///         format, which is the shape you get from the UI's "export batch", and
///         the shape FraxFinance's `SafeTxHelper.writeTxs` writes:
///
///           { version, chainId, createdAt, meta, transactions: [ {to,value,data,operation} ] }
///
///         https://github.com/FraxFinance/frax-standard-solidity/blob/master/src/SafeTxHelper.sol
///
///         Note what this format does *not* contain: no Safe address, no nonce, no
///         gas fields. A batch on its own is not yet a transaction. It becomes one
///         only once it is bound to a specific Safe at a specific nonce and folded
///         into a `multiSend` delegatecall. `forge-attest` does that binding from
///         its config, which is why the Safe address and nonce live there rather
///         than here.
///
///         `createdAt` is deliberately a wall-clock stamp, exactly as `SafeTxHelper`
///         writes it. That means the raw bytes differ between runs. It is why
///         `forge-attest` pins a *canonical* digest, computed after folding and
///         normalisation, rather than only a byte-exact sha256 of this file.
contract BuildSafeBatch {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant CHAIN_ID = 1; // Ethereum mainnet

    // Payload: revoke an old spender's allowance, then move 1 USDC to the burn
    // address. Two calls that must land together or not at all, which is the
    // reason to batch them in the first place.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant OLD_SPENDER = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address internal constant RECIPIENT = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant AMOUNT = 1_000000; // 1 USDC, 6 decimals

    function run() external {
        bytes memory revokeCall = abi.encodeWithSignature("approve(address,uint256)", OLD_SPENDER, 0);
        bytes memory transferCall = abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, AMOUNT);

        string memory json = string.concat(
            "{\n",
            '  "version": "1.0",\n',
            '  "chainId": ',   vm.toString(CHAIN_ID),               ",\n",
            '  "createdAt": ', vm.toString(block.timestamp * 1000), ",\n",
            '  "meta": {\n',
            '    "name": "Transactions Batch",\n',
            '    "description": ""\n',
            "  },\n",
            '  "transactions": [\n',
            _tx(USDC, 0, revokeCall),   ",\n",
            _tx(USDC, 0, transferCall), "\n",
            "  ]\n",
            "}\n"
        );

        string memory outDir = string.concat(vm.projectRoot(), "/out");
        vm.createDir(outDir, true);
        vm.writeFile(string.concat(outDir, "/safe-batch.json"), json);
    }

    /// @dev One batch entry. `value` and `operation` are quoted strings, which
    ///      matches what `SafeTxHelper` emits. It writes them with
    ///      `Strings.toString`.
    function _tx(address to, uint256 value, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            "    {",
            ' "to": "',        vm.toString(to),    '",',
            ' "value": "',     vm.toString(value), '",',
            ' "data": "',      vm.toString(data),  '",',
            ' "operation": "0"',
            " }"
        );
    }
}
