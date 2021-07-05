// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./library/SafeMath.sol";
import "./library/SafeERC20.sol";
import "./interfaces/IDino.sol";
import "./interfaces/IMapper.sol";

contract Auction {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    bytes4 internal constant ON_ERC721_RECEIVED = 0x150b7a02;

    struct AuctionInfo {
        IERC20 bidToken;
        IERC721 bidNft;
        address beneficiary;
        address currentBidAddress;
        uint bidTokenId;
        uint32 endBlock;
        uint112 currentBidAmount;
        bool isDino;
    }

    IDino public dino;
    mapping(address => bool) public canBeBidToken;
    mapping(address => mapping(uint => uint)) public bidAmounts;
    AuctionInfo[] public auctionInfos;

    event NewAuction(
        uint indexed auctionId,
        address indexed bidTokenAddress,
        address indexed bidNftAddress,
        address beneficiary,
        uint bidTokenId,
        uint endBlock,
        uint minimumBidAmount,
        bool isDino);

    event Bid(
        uint indexed auctionId,
        address indexed account,
        uint amount);

    event Claim(
        uint indexed auctionId,
        address indexed account);

    event NewBidToken(address newBidToken);

    constructor (address _dino) {
        dino = IDino(_dino);
        canBeBidToken[_dino] = true;

        auctionInfos.push(AuctionInfo(
            IERC20(address(0)),
            IERC721(address(0)),
            address(0),
            address(0),
            0,
            0,
            0,
            false));
    }

    function setDino(address _dino) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        dino = IDino(_dino);
    }

    function addBidToken(address newBidToken) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        canBeBidToken[newBidToken] = true;

        emit NewBidToken(newBidToken);
    }

    function createAuction(
        address bidTokenAddress,
        address bidNftAddress,
        address beneficiary,
        uint bidTokenId,
        uint endBlock,
        uint minimumBidAmount
    ) public {

        IMapper mapper = IMapper(dino.mapper());
        (address nft, ) = mapper.dino20ToNFTInfo(bidTokenAddress);

        require(canBeBidToken[bidTokenAddress] || nft != address(0), "Dino: bid token"); //dino bid or dino20 bid

        (address dino20, ) = mapper.tokenInfos(bidNftAddress, bidTokenId);

        IERC721 bidNft = IERC721(bidNftAddress);
        if(dino20 == address(0)) { //not dino20, external
            bidNft.safeTransferFrom(msg.sender, address(this), bidTokenId);
        } else { //dino20 (no nft transfer)
            IERC20 idino20 = IERC20(dino20);
            uint ownerMinimumAmount = idino20.totalSupply()
                .mul(dino.ownPercentage())
                .div(1e18);
            idino20.safeTransferFrom(msg.sender, address(this), ownerMinimumAmount);
        }

        auctionInfos.push(AuctionInfo(
            IERC20(bidTokenAddress),
            bidNft,
            beneficiary,
            address(0),
            bidTokenId,
            safe32(endBlock),
            safe112(minimumBidAmount),
            dino20 != address(0)));

        bidAmounts[beneficiary][auctionInfos.length - 1] = 1; //check beneficiary claim

        emit NewAuction(
            auctionInfos.length - 1,
            bidTokenAddress,
            bidNftAddress,
            beneficiary,
            bidTokenId,
            endBlock,
            minimumBidAmount,
            dino20 != address(0));

    }

    function bid(
        uint auctionId,
        uint bidAmount
    ) public {
        AuctionInfo storage auctionInfo = auctionInfos[auctionId];
        require(msg.sender != auctionInfo.beneficiary, "Dino: beneficiary"); //beneficiary cannot bid
        require(block.number < auctionInfo.endBlock, "Dino: over");
        require(auctionInfo.currentBidAmount < bidAmount, "Dino: bid amount");

        auctionInfo.bidToken.safeTransferFrom(
            msg.sender,
            address(this),
            bidAmount.sub(bidAmounts[msg.sender][auctionId]));

        bidAmounts[msg.sender][auctionId] = bidAmount;

        auctionInfo.currentBidAmount = safe112(bidAmount);
        auctionInfo.currentBidAddress = msg.sender;

        emit Bid(
            auctionId,
            msg.sender,
            bidAmount);
    }

    function claim(
        uint auctionId
    ) public {
        AuctionInfo storage auctionInfo = auctionInfos[auctionId];
        require(bidAmounts[msg.sender][auctionId] > 0, "Dino: only once"); //once check

        emit Claim(
            auctionId,
            msg.sender);

        if(msg.sender != auctionInfo.currentBidAddress && msg.sender != auctionInfo.beneficiary) { //refund
            auctionInfo.bidToken.safeTransfer(msg.sender, bidAmounts[msg.sender][auctionId]);
            delete bidAmounts[msg.sender][auctionId];
            return;
        }

        require(block.number >= auctionInfo.endBlock, "Dino: not over"); //claim period check
        delete bidAmounts[msg.sender][auctionId];

        if(msg.sender == auctionInfo.beneficiary && auctionInfo.currentBidAddress != address(0)) { //someone bid
            uint feeAmount = uint(auctionInfo.currentBidAmount)
                .mul(dino.auctionFeePercentage())
                .div(1e18); //fee
            auctionInfo.bidToken.safeTransfer(dino.receiver(), feeAmount);
            auctionInfo.bidToken.safeTransfer(msg.sender, uint(auctionInfo.currentBidAmount).sub(feeAmount));
            return;
        }

        if(auctionInfo.isDino) { //claim or refund if no one bids
            IMapper mapper = IMapper(dino.mapper());
            (address dino20, ) = mapper.tokenInfos(address(auctionInfo.bidNft), auctionInfo.bidTokenId);

            IERC20 idino20 = IERC20(dino20);
            uint ownerMinimumAmount = idino20.totalSupply()
                .mul(dino.ownPercentage())
                .div(1e18);
            idino20.safeTransfer(msg.sender, ownerMinimumAmount);
        } else {
            auctionInfo.bidNft.safeTransferFrom(address(this), msg.sender, auctionInfo.bidTokenId);
        }
    }

    function safe112(uint amount) internal pure returns (uint112) {
        require(amount < 2**112, "Dino: 112");
        return uint112(amount);
    }

    function safe32(uint amount) internal pure returns (uint32) {
        require(amount < 2**32, "Dino: 32");
        return uint32(amount);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
        return ON_ERC721_RECEIVED;
    }
}