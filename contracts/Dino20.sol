// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IDino.sol";
import "./interfaces/IController.sol";
import "./library/ERC20.sol";

contract Dino20 is ERC20 {
    IDino public dino;

    constructor(
        string memory name_,
        string memory symbol_,
        address _dino,
        uint _initialSupply
    ) ERC20(name_, symbol_) {
        dino = IDino(_dino);
        _mint(msg.sender, _initialSupply);
    }

    function setDino(address _dino) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        dino = IDino(_dino);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if(from != address(0)) {
            IController(dino.controller()).refreshOwner(from, to, amount);
        }
    }
}