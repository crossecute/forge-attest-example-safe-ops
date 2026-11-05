// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeTransferExample} from "./SafeTransferExample.sol";

contract BuildSafeDecodedBatch is SafeTransferExample {
    function run() external {
        // The policy target is illustrative, with no deployed contract assumed.
        _write(
            "safe-decoded-batch.json",
            string.concat(
                '{"version":"1.0","chainId":"1","createdAt":0,',
                '"meta":{"name":"Decoded scalar calls","createdFromSafeAddress":"',
                vm.toString(SAFE),
                '"},',
                '"transactions":[{"to":"',
                vm.toString(USDC),
                '","value":"0","data":null,',
                '"contractMethod":{"name":"transfer","payable":false,"inputs":[',
                '{"name":"to","type":"address"},{"name":"amount","type":"uint256"}]},',
                '"contractInputsValues":{"to":"',
                vm.toString(RECIPIENT),
                '","amount":"',
                vm.toString(AMOUNT),
                '"}},',
                '{"to":"0x2222222222222222222222222222222222222222","value":"0","data":null,',
                '"contractMethod":{"name":"setPolicy","payable":false,"inputs":[',
                '{"name":"enabled","type":"bool"},{"name":"level","type":"uint8"}]},',
                '"contractInputsValues":{"enabled":"true","level":"255"}}]}\n'
            )
        );
    }
}
