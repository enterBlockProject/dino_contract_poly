// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../library/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }

    function mint(address account) public {
        _mint(account, 1000);
    }

    function mint(address account, uint amount) public {
        _mint(account, amount);
    }
}