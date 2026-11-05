// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeExample} from "./SafeExample.sol";

abstract contract SafeTransferExample is SafeExample {
    address internal constant SAFE = 0x111CEEee040739fD91D29C34C33E6B3E112F2177;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant RECIPIENT = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant AMOUNT = 1_000_000;

    function _data() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("transfer(address,uint256)", RECIPIENT, AMOUNT);
    }

    function _fields(uint256 nonce, bool includeAddresses) internal pure returns (string memory) {
        return string.concat(
            '"to":"',
            vm.toString(USDC),
            '","value":"0","data":"',
            vm.toString(_data()),
            '","operation":"0","safeTxGas":"0","baseGas":"0","gasPrice":"0",',
            includeAddresses
                ? '"gasToken":"0x0000000000000000000000000000000000000000","refundReceiver":"0x0000000000000000000000000000000000000000",'
                : "",
            '"nonce":"',
            vm.toString(nonce),
            '"'
        );
    }

    function _hash(uint256 nonce) internal pure returns (bytes32) {
        bytes32 domain =
            keccak256(abi.encode(keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"), 1, SAFE));
        bytes32 message = keccak256(
            abi.encode(
                keccak256(
                    "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
                ),
                USDC,
                0,
                keccak256(_data()),
                uint8(0),
                0,
                0,
                0,
                address(0),
                address(0),
                nonce
            )
        );
        return keccak256(abi.encodePacked(hex"1901", domain, message));
    }
}
