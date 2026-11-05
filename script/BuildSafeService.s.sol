// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeTransferExample} from "./SafeTransferExample.sol";

contract BuildSafeService is SafeTransferExample {
    function run() external {
        _write("safe-service.json", _request(46, true));
        _write("safe-service-utils.json", _request(47, false));
    }

    function _request(uint256 nonce, bool includeAddresses) internal pure returns (string memory) {
        string memory txHash = vm.toString(abi.encodePacked(_hash(nonce)));
        // Chain and omitted safe-utils addresses are bound by the reviewed claim.
        return string.concat(
            "{",
            includeAddresses ? string.concat('"safe":"', vm.toString(SAFE), '",') : "",
            _fields(nonce, includeAddresses),
            ',"contractTransactionHash":"',
            txHash,
            '","safeTxHash":"',
            txHash,
            '","origin":"forge-attest v1.3.0 example"}\n'
        );
    }
}
