// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../library/ERC20.sol";
import "../library/ERC721Enumerable.sol";

contract MockERC721 is ERC721Enumerable {
    constructor() ERC721("test721", "test721") {

    }

    function mint(address account, uint tokenId) public {
        _safeMint(account, tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nft.dinoart.io/api/v0/nft/token/3/";
    }
}