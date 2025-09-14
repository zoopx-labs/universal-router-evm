// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../utils/Context.sol";
import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";

contract ERC20 is Context, IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }
    function allowance(address owner, address spender) public view override returns (uint256) { return _allowances[owner][spender]; }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount); return true;
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = msg.sender;
        uint256 currentAllowance = _allowances[from][spender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(from, spender, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        uint256 fromBal = _balances[from];
        require(fromBal >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBal - amount;
        _balances[to] += amount;
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to zero");
        _totalSupply += amount;
        _balances[account] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0) && spender != address(0), "ERC20: approve zero");
        _allowances[owner][spender] = amount;
    }
}
