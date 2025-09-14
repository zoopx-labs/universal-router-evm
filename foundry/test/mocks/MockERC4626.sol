// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC4626 is ERC20 {
    IERC20 public asset;

    constructor(string memory name, string memory symbol, IERC20 _asset) ERC20(name, symbol) {
        asset = _asset;
    }

    // deposit pulls assets via transferFrom and mints 1:1 shares
    function deposit(uint256 assets, address receiver) external returns (uint256) {
        require(assets > 0, "zero assets");
        uint256 balBefore = asset.balanceOf(address(this));
        asset.transferFrom(msg.sender, address(this), assets);
        uint256 received = asset.balanceOf(address(this)) - balBefore;
        require(received == assets, "fee-on-transfer not supported");
        _mint(receiver, assets);
        return assets;
    }
}
