// Minimal shim for forge-std Test.sol to satisfy imports during local test runs
// This file is intentionally minimal and only provides the `Test` contract and a `vm` placeholder used in tests.
// For real projects, add forge-std as a dependency: https://github.com/foundry-rs/forge-std

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Minimal Vm interface used by tests in this workspace. This is only a compile-time shim.
interface Vm {
    function addr(uint256 privateKey) external view returns (address);
    function sign(uint256 privateKey, bytes32 digest) external view returns (uint8 v, bytes32 r, bytes32 s);
    function startPrank(address sender) external;
    function stopPrank() external;
    function prank(address sender) external;
    function expectRevert() external;
    function expectRevert(bytes calldata) external;
    function expectRevert(bytes4) external;
}

// A placeholder `vm` variable. In real foundry runs this is injected; here it's declared as an external contract
// so calls compile but will revert if executed outside Foundry. That's acceptable for compile-time tests.
Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

contract Test {
    // Minimal assertion helpers used by tests in this workspace.
    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assertEq uint256");
    }
    function assertEq(address a, address b) internal pure {
        require(a == b, "assertEq address");
    }
    function assertEq(bytes32 a, bytes32 b) internal pure {
        require(a == b, "assertEq bytes32");
    }
}
