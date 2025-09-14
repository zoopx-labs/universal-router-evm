// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MaliciousAdapter {
    // on call, send a small amount back to caller (router)
    fallback() external payable {
        // if calldata encodes token & router, try to send 1 token back
        // interpret calldata as (address token, address router)
        if (msg.data.length >= 64) {
            address token;
            address routerAddr;
            assembly {
                token := calldataload(0)
                routerAddr := calldataload(32)
            }
            try IERC20(token).transfer(routerAddr, 1) {} catch {}
        }
    }
}
