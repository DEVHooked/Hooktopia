// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// Interface for NFT contract
interface INFT {
    function redeem(address to, uint256 tokenId) external;
}

contract HooktopiaCompass is ERC721, ERC721Enumerable, AccessControl {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    enum SaleStates {
        NotStarted,
        AllowlistOnly,
        PublicSale,
        SoldOut
    }

    Counters.Counter private _tokenIdCounter;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant maxSupply = 6666;
    uint256 public constant maxGoldSupply = 1111;
    uint256 public constant maxSilverSupply = maxSupply - maxGoldSupply; // 6666 - 1111 = 5555
    uint256 public constant MINTS_PER_WALLET = 3;
    address public constant HOOKTokenAddress = 0xa260E12d2B924cb899AE80BB58123ac3fEE1E2F0;

    uint256 public totalGoldSupply;
    uint256 public totalSilverSupply;
    uint256 public reservedGoldSupply;
    uint256 public reservedSilverSupply;

    // Price for the Gold allowlist mint and public mint
    uint256 public allowlistPriceGold = 0 ether;
    uint256 public publicPriceGold = 0 ether;

    // Price for the Silver allowlist mint and public mint
    uint256 public allowlistPriceSilver = 0 ether;
    uint256 public publicPriceSilver = 0 ether;

    SaleStates public saleState = SaleStates.NotStarted;

    address public mintSigner;

    bool public burnOpen = false;

    INFT public nftContract;

    bytes32 public constant MINT_HASH_TYPE = keccak256("mint");

    // Mapping of token ID to token type
    mapping(uint256 => uint8) public tokenTypes;

    uint64[] public remainingGoldCompass;
    uint64[] public remainingSilverCompass;

    mapping(address => uint8) public mintedCompass;

    constructor(address _signer) ERC721("Hooktopia Compass ", "HC") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        mintSigner = _signer;

        for (uint64 i = 0; i < maxGoldSupply; i++) { // Gold from 0 to 1110
            remainingGoldCompass.push(i);
        }
        for (uint64 i = uint64(maxGoldSupply); i < maxSupply; i++) { // Silver from 1111 to 6665
            remainingSilverCompass.push(i);
        }
    }

    function contractURI() public pure returns (string memory) {
        return "https://ipfs.hooked.io/contract-metadata/hooktopia-compass.json";
    }

    function allowlistMint(uint8 numberOfTokens, uint8 tokenType, bytes calldata signature) external {
        require(saleState == SaleStates.AllowlistOnly, "Allowlist mint not started");
        mint(numberOfTokens,tokenType,allowlistPriceGold,allowlistPriceSilver,signature);
    }

    function publicMint(uint8 numberOfTokens, uint8 tokenType, bytes calldata signature) external {
        require(saleState == SaleStates.PublicSale, "Sale not started");
        mint(numberOfTokens,tokenType,publicPriceGold,publicPriceSilver,signature);
    }

    function mint(uint8 numberOfTokens, uint8 tokenType, uint256 goldPrice, uint256 silverPrice, bytes calldata signature) internal {
        require(numberOfTokens > 0, "numberOfTokens cannot be 0");
        require(numberOfTokens + mintedCompass[msg.sender] <= MINTS_PER_WALLET, "Exceeds wallet mint limit");
        require(tokenType == 0 || tokenType == 1, "Invalid token type");

        // Verify the signature
        bytes32 message = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(MINT_HASH_TYPE, msg.sender)));
        require(SignatureChecker.isValidSignatureNow(mintSigner, message, signature),"Invalid signature");

        if (tokenType == 0) { // Gold
            require(totalGoldSupply + numberOfTokens <= maxGoldSupply, "Exceeds Gold supply");
            uint256 allowance = IERC20(HOOKTokenAddress).allowance(msg.sender, address(this));
            uint256 price = goldPrice * numberOfTokens;
            require(allowance >= price, "Not enough allowance");
            IERC20(HOOKTokenAddress).safeTransferFrom(msg.sender, address(this), price);
            for (uint256 i = 0; i < numberOfTokens; i++) {
                _mintByType(msg.sender, tokenType);
                totalGoldSupply++;
            }
        } else { // Silver
            require(totalSilverSupply + numberOfTokens <= maxSilverSupply, "Exceeds Silver supply");
            uint256 allowance = IERC20(HOOKTokenAddress).allowance(msg.sender, address(this));
            uint256 price = silverPrice * numberOfTokens;
            require(allowance >= price, "Not enough allowance");
            IERC20(HOOKTokenAddress).safeTransferFrom(msg.sender, address(this), price);
            for (uint256 i = 0; i < numberOfTokens; i++) {
                 _mintByType(msg.sender, tokenType);
                totalSilverSupply++;
            }
        }
        mintedCompass[msg.sender] += numberOfTokens;
    }

    function ownerMint(address to, uint8 numberOfTokens, uint8 tokenType) external onlyRole(MINTER_ROLE) {
        require(numberOfTokens > 0, "numberOfTokens cannot be 0");
        require(tokenType == 0 || tokenType == 1, "Invalid token type");

        if (tokenType == 0) { // Gold
            require(reservedGoldSupply + numberOfTokens <= maxGoldSupply, "Exceeds Gold supply");
            for (uint256 i = 0; i < numberOfTokens; i++) {
                _mintByType(to, tokenType);
                reservedGoldSupply++;
            }
        } else { // Silver
            require(reservedSilverSupply + numberOfTokens <= maxSilverSupply, "Exceeds Silver supply");
            for (uint256 i = 0; i < numberOfTokens; i++) {
                _mintByType(to, tokenType);
                reservedSilverSupply++;
            }
        }
        mintedCompass[to] += numberOfTokens;
    }

    function _mintByType(address _to, uint8 tokenType) private {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(_to, tokenId);
        tokenTypes[tokenId] = tokenType;
    }

    function setNFTContract(address _nftContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        nftContract = INFT(_nftContract);
    }

    function setSaleState(SaleStates _saleState) external onlyRole(DEFAULT_ADMIN_ROLE) {
        saleState = _saleState;
    }

    function setBurnOpen(bool _burnOpen) external onlyRole(DEFAULT_ADMIN_ROLE) {
        burnOpen = _burnOpen;
    }

    function setMintSigner(address _mintSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintSigner = _mintSigner;
    }

    function setGoldPrices(uint256 _allowlistPriceGold, uint256 _publicPriceGold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowlistPriceGold = _allowlistPriceGold;
        publicPriceGold = _publicPriceGold;
    }

    function setSilverPrices(uint256 _allowlistPriceSilver, uint256 _publicPriceSilver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowlistPriceSilver = _allowlistPriceSilver;
        publicPriceSilver = _publicPriceSilver;
    }

    function burnCompass(uint256[] calldata tokenIds) external {
        require(burnOpen, "Burn not open");
        require(address(nftContract) != address(0), "NFT not set");

        for (uint256 i; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];

            // Validate ownership or approval before burning
            require(ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender), "Not owner or approved");
            _burn(tokenId);

            uint8 tokenType = tokenTypes[tokenId];

            // Mint new NFT
            nftContract.redeem(msg.sender, followCompass(tokenType));

            // Increment counter
            i++;
        }
    }

    function followCompass(uint8 tokenType) private returns (uint256){
        require(tokenType == 0 || tokenType == 1, "Invalid token type");
        require(tokenType == 0 ? remainingGoldCompass.length > 0 : remainingSilverCompass.length > 0, "No Can left");

        uint256 tokenId;
        if (tokenType == 0) { // Gold
            uint256 index = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % remainingGoldCompass.length;
            tokenId = remainingGoldCompass[index];
            remainingGoldCompass[index] = remainingGoldCompass[remainingGoldCompass.length - 1];
            remainingGoldCompass.pop();
        } else { // Silver
            uint256 index = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % remainingSilverCompass.length;
            tokenId = remainingSilverCompass[index];
            remainingSilverCompass[index] = remainingSilverCompass[remainingSilverCompass.length - 1];
            remainingSilverCompass.pop();
        }

        return tokenId;
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
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * Function to retrieve the metadata uri for a given token. Reverts for tokens that don't exist.
     * @param tokenId Token Id to get metadata for
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        string memory tokenType = tokenTypes[tokenId] == 0 ? "Gold" : "Silver";
        string memory imageURL = tokenTypes[tokenId] == 0 ? "https://ipfs.hooked.io/compass/QmWzWvZ9ksXC5d1tKcUvi86AixgmVM96QrXQcfCDQMXbAY.png" : "https://ipfs.hooked.io/compass/Qmf4ouJ2iJQBQSf7uCWmLx99gJdZtBfzJ6m2BjdzekmRJg.png";
        string memory description = tokenTypes[tokenId] == 0 ? "A compass made of gold can indicate the location of strong miracles which in hooktopia.According to the legend, miracles can bring powerful blessing to nourish your land" : "A compass made of silver can indicate the location of ordinary miracles which in hooktopia.According to the legend, miracles can bring powerful blessing to nourish your land";
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Hooktopia Compass #',Strings.toString(tokenId),'", "description": "',description,'", "image": "',imageURL,'", "attributes": [{"trait_type":"Trait","value":"Compass"},{"trait_type": "Material", "value": "', tokenType, '"}]}'))));
        string memory output = string(abi.encodePacked('data:application/json;base64,', json));
        return output;
    }
}