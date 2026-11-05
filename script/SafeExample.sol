// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface Vm {
    function toString(address value) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
    function toString(bytes calldata value) external pure returns (string memory);
    function projectRoot() external view returns (string memory);
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
}

abstract contract SafeExample {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function _write(string memory name, string memory json) internal {
        string memory outDir = string.concat(vm.projectRoot(), "/out");
        vm.createDir(outDir, true);
        vm.writeFile(string.concat(outDir, "/", name), json);
    }
}
