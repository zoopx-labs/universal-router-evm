// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract TargetAdapterMock {
    address public lastCaller;
    bytes public lastPayload;
    uint256 public callCount;

    event Executed(address caller, bytes payload, uint256 bal);

    fallback() external payable {
        lastCaller = msg.sender;
        lastPayload = msg.data;
        callCount += 1;
        emit Executed(msg.sender, msg.data, address(this).balance);
    }

    receive() external payable {
        lastCaller = msg.sender;
        lastPayload = "";
        callCount += 1;
        emit Executed(msg.sender, "", address(this).balance);
    }
}
