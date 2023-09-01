// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";


contract Hooktopia is ERC721, ERC721Enumerable, Ownable {
    address immutable public compassAddress;
    string private _baseTokenURI;

    constructor(address _compass) ERC721("Hooktopia", "HT") {
        compassAddress = _compass;
    }

    function redeem(address to, uint256 tokenId) external {
        require(msg.sender == compassAddress, "Hooktopia: Only Compass can redeem");
        _safeMint(to, tokenId);
    }

    function setBaseTokenURI(string calldata _uri) external onlyOwner {
        _baseTokenURI = _uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "Hooktopia: URI query for nonexistent token");
        return string(abi.encodePacked(_baseURI(), Strings.toString(_tokenId), ".json"));
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}