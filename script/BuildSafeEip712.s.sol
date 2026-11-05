// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeTransferExample} from "./SafeTransferExample.sol";

contract BuildSafeEip712 is SafeTransferExample {
    function run() external {
        _write("safe-eip712.json", _envelope(44, true));
        _write("safe-eip712-utils.json", _envelope(45, false));
    }

    function _envelope(uint256 nonce, bool includeDomainType) internal pure returns (string memory) {
        return string.concat(
            '{"types":{',
            includeDomainType
                ? '"EIP712Domain":[{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],'
                : "",
            '"SafeTx":[',
            '{"name":"to","type":"address"},{"name":"value","type":"uint256"},',
            '{"name":"data","type":"bytes"},{"name":"operation","type":"uint8"},',
            '{"name":"safeTxGas","type":"uint256"},{"name":"baseGas","type":"uint256"},',
            '{"name":"gasPrice","type":"uint256"},{"name":"gasToken","type":"address"},',
            '{"name":"refundReceiver","type":"address"},{"name":"nonce","type":"uint256"}]},',
            '"primaryType":"SafeTx","domain":{"chainId":"1","verifyingContract":"',
            vm.toString(SAFE),
            '"},"message":{',
            _fields(nonce, true),
            "}}\n"
        );
    }
}
