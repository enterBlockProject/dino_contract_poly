// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IDino.sol";
import "./library/ERC721Enumerable.sol";

contract Dino721 is ERC721Enumerable {

    IDino public dino;

    constructor(address _dino) ERC721("Dino721", "Dino721") {
        dino = IDino(_dino);
    }

    function setDino(address _dino) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        dino = IDino(_dino);
    }

    function mint(address account, uint tokenId) public {
        require(msg.sender == dino.controller(), "Dino: controller");
        _safeMint(account, tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nft.dinoart.io/api/v0/nft/token/3/";
    }
}