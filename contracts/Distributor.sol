// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IERC20.sol";
import "./library/SafeMath.sol";
import "./library/SafeERC20.sol";
import "./interfaces/IDino.sol";
import "./interfaces/IMapper.sol";
import "./interfaces/IWMATIC.sol";

contract Distributor {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;

    IDino public dino;

    uint public tokenPerBlock;
    uint public startBlock;
    uint public endBlock;
    uint public totalWeight;

    uint public bonusAmount;
    uint public bonusEndBlock;

    poolInfo[] public rewardPools;

    struct userInfo {
        uint minusAmount;
        uint depositAmount;
    }

    struct poolInfo {
        address token;
        uint rewardRate;
        uint lastBlock;
        uint totalBalance;
        uint weight;
    }

    mapping (address => mapping (uint => userInfo)) public userInfos;
    mapping (address => bool) public bonusClaimed;

    event NewBonusAmount(uint newBonusAmount);
    event NewBonusEndBlock(uint newBonusEndBlock);
    event ClaimBonus(address indexed dino20, address indexed account, uint amount);

    event NewRewardPool(uint indexed idx, address rewardPool, uint weight);
    event NewWeight(uint indexed idx, uint weight);

    event Deposit(
        address indexed account,
        uint indexed idx,
        uint amount);

    event Withdrawal(
        address indexed account,
        uint indexed idx,
        uint amount);

    event ClaimReward(
        address indexed account,
        uint indexed idx,
        uint amount);

    constructor (
        address _dino,
        uint _tokenPerBlock,
        uint _startBlock,
        uint _endBlock,
        uint _bonusAmount,
        uint _bonusEndBlock
    ) {
        dino = IDino(_dino);
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;

        bonusAmount = _bonusAmount;
        bonusEndBlock = _bonusEndBlock;
    }

    function setDino(address _dino) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        dino = IDino(_dino);
    }

    function setBonusAmount(uint _bonusAmount) public {
        require(msg.sender == dino.admin(), "Dino: admin");

        bonusAmount = _bonusAmount;

        emit NewBonusAmount(_bonusAmount);
    }

    function setBonusEndBlock(uint _bonusEndBlock) public {
        require(msg.sender == dino.admin(), "Dino: admin");

        bonusEndBlock = _bonusEndBlock;

        emit NewBonusEndBlock(_bonusEndBlock);
    }

    function addRewardPool(address token, uint weight) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        for (uint i = 0; i < rewardPools.length; i++) {
            update(i);
        }
        rewardPools.push(
            poolInfo(
                token,
                0,
                startBlock > block.number ? startBlock : block.number,
                0,
                weight
            )
        );
        totalWeight = totalWeight.add(weight);
        emit NewRewardPool(rewardPools.length - 1, token, weight);
    }

    function setWeight(uint idx, uint weight) public {
        require(msg.sender == dino.admin(), "Dino: admin");
        for (uint i = 0; i < rewardPools.length; i++) {
            update(i);
        }
        totalWeight = totalWeight
            .sub(rewardPools[idx].weight)
            .add(weight);
        rewardPools[idx].weight = weight;

        emit NewWeight(idx, weight);
    }

    function rewardPerPeriod(uint lastBlock) public view returns (uint) {
        uint currentBlock = block.number < startBlock
            ? startBlock
            : (block.number > endBlock ? endBlock : block.number);

        return currentBlock
            .sub(lastBlock)
            .mul(tokenPerBlock);
    }

    function rewardAmount(uint idx, address account) public view returns (uint) {
        poolInfo memory pool = rewardPools[idx];
        userInfo memory user = userInfos[account][idx];

        uint rewardRate = pool.rewardRate;
        if (block.number > pool.lastBlock && pool.totalBalance != 0) {
            rewardRate = rewardRate.add(
                rewardPerPeriod(pool.lastBlock)
                    .mul(pool.weight)
                    .div(totalWeight)
                    .mul(1e18)
                    .div(pool.totalBalance));
        }
        return user.depositAmount
            .mul(rewardRate)
            .div(1e18)
            .sub(user.minusAmount);
    }

    function deposit(uint idx, uint amount) public payable {
        require(idx < rewardPools.length, "Dino: pool");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        if (user.depositAmount > 0) {
            claim(idx);
        } else {
            update(idx);
        }

        pool.totalBalance = pool.totalBalance.add(amount);

        user.depositAmount = user.depositAmount.add(amount);
        user.minusAmount = user.depositAmount
            .mul(pool.rewardRate)
            .div(1e18);

        if(pool.token == wmatic) {
            require(amount == msg.value, "Dino: matic amount");
            IWMATIC(wmatic).deposit{value: amount}();
        } else {
            IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit Deposit(msg.sender, idx, amount);
    }

    function withdraw(uint idx, uint amount) public {
        require(idx < rewardPools.length, "Dino: pool");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        claim(idx);

        pool.totalBalance = pool.totalBalance.sub(amount);

        user.depositAmount = user.depositAmount.sub(amount);
        user.minusAmount = user.depositAmount
            .mul(pool.rewardRate)
            .div(1e18);

        if(pool.token == wmatic) {
            IWMATIC(wmatic).withdraw(amount);
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(pool.token).safeTransfer(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, idx, amount);
    }

    function update(uint idx) private {
        poolInfo storage pool = rewardPools[idx];

        if (block.number <= pool.lastBlock) {
            return;
        }

        uint currentBlock = block.number >= endBlock
            ? endBlock
            : block.number;

        if (pool.totalBalance == 0) {
            pool.lastBlock = currentBlock;
            return;
        }

        uint rewardPerPool = rewardPerPeriod(pool.lastBlock)
            .mul(pool.weight)
            .div(totalWeight);

        pool.rewardRate = pool.rewardRate
            .add(rewardPerPool
                .mul(1e18)
                .div(pool.totalBalance));

        pool.lastBlock = currentBlock;
    }

    function claim(uint idx) public {
        require(idx < rewardPools.length, "Dino: pool");
        userInfo storage user = userInfos[msg.sender][idx];

        update(idx);

        uint reward = user.depositAmount
            .mul(rewardPools[idx].rewardRate)
            .div(1e18)
            .sub(user.minusAmount);

        if(reward > 0) {
            user.minusAmount = reward.add(user.minusAmount);
            dino.mint(msg.sender, reward);
        }

        emit ClaimReward(msg.sender, idx, reward);
    }

    function claimBonusAmount(address dino20) public {
        require(!bonusClaimed[dino20], "Dino: claimed");
        require(block.number < bonusEndBlock, "Dino: claimed");

        IMapper mapper = IMapper(dino.mapper());

        (address nft, uint tokenId) = mapper.dino20ToNFTInfo(dino20);
        (, address owner) = mapper.tokenInfos(nft, tokenId);

        require(msg.sender == owner, "Dino: owner");
        bonusClaimed[dino20] = true;
        dino.mint(msg.sender, bonusAmount);

        emit ClaimBonus(
            dino20,
            msg.sender,
            bonusAmount);
    }

    function getAllPoolLists() public view returns (address[] memory, uint[] memory, uint[] memory){
        address[] memory tokens = new address[](rewardPools.length);
        uint[] memory totalBalances = new uint[](rewardPools.length);
        uint[] memory weights = new uint[](rewardPools.length);
        for(uint i = 0; i < rewardPools.length; i++) {
            poolInfo memory pool = rewardPools[i];
            tokens[i] = pool.token;
            totalBalances[i] = pool.totalBalance;
            weights[i] = pool.weight;
        }
        return (tokens, totalBalances, weights);
    }

    receive() external payable {
        assert(msg.sender == wmatic);
    }
}