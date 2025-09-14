// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Minimal ERC20 with fee-on-transfer implemented in transfer/transferFrom
contract FeeOnTransferMockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    uint256 public feeBps;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _feeBps) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        feeBps = _feeBps;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "bal");
        uint256 fee = (amount * feeBps) / 10000;
        uint256 net = amount - fee;
        balanceOf[from] -= amount;
        balanceOf[to] += net;
        if (fee > 0) balanceOf[address(this)] += fee;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
