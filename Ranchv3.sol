// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC721Receiver.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./EnumerableSet.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "https://github.com/Uniswap/v3-core/blob/0.8/contracts/libraries/FullMath.sol";
import "./NFTPositionInfo.sol";
import "./IUniswapV3Factory.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FixedPoint128.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FixedPoint96.sol";
import "https://github.com/Uniswap/v3-core/blob/0.8/contracts/libraries/TickMath.sol";


contract NFTVesting is IERC721Receiver {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;

    IERC20 public staiKToken;
    IERC721 public nftToken;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniswapV3Factory public factory;

    uint256 private constant REWARD_PERIOD = 28 days;
    uint256 public periodEnd;

    EnumerableSet.UintSet private tokens;
    uint256 public totalStakedValue;
    uint256 public rewardPool;

    struct UserInfo {
        uint256 depositTime;
        uint256 stakedValue;
    }

    mapping(uint256 => UserInfo) public userInfo;

constructor(
    INonfungiblePositionManager _nonfungiblePositionManager,
    IUniswapV3Factory _factory
//    uint256 _rewardDuration
) {
    nonfungiblePositionManager = _nonfungiblePositionManager;
    factory = _factory;

}

    function deposit(uint256 tokenId) external {
        nftToken.transferFrom(msg.sender, address(this), tokenId);
        uint256 nftValue = _getNFTValue(tokenId);

        UserInfo storage user = userInfo[tokenId];
        user.depositTime = block.timestamp;
        user.stakedValue = nftValue;

        totalStakedValue = totalStakedValue.add(nftValue);
        tokens.add(tokenId);
    }

    function withdraw(uint256 tokenId) external {
        require(nftToken.ownerOf(tokenId) == address(this), "Token not deposited");

        uint256 reward = calculateReward(tokenId);
        if (reward > 0) {
            staiKToken.transfer(msg.sender, reward);
            rewardPool = rewardPool.sub(reward);
        }

        UserInfo storage user = userInfo[tokenId];
        totalStakedValue = totalStakedValue.sub(user.stakedValue);
        tokens.remove(tokenId);

        delete userInfo[tokenId];
        nftToken.transferFrom(address(this), msg.sender, tokenId);
    }

    function calculateReward(uint256 tokenId) public view returns (uint256) {
        UserInfo storage user = userInfo[tokenId];
        if (user.depositTime == 0) return 0;

        uint256 timeEnd = block.timestamp < periodEnd ? block.timestamp : periodEnd;
        uint256 timeElapsed = timeEnd.sub(user.depositTime);
        uint256 timeRatio = timeElapsed.mul(1e18).div(REWARD_PERIOD);
        uint256 valueRatio = user.stakedValue.mul(1e18).div(totalStakedValue);
        uint256 totalRatio = timeRatio.mul(valueRatio).div(1e18);

        return rewardPool.mul(totalRatio).div(1e18);
    }

    function _getNFTValue(uint256 tokenId) internal view returns (uint256) {
        (, , , uint128 liquidity) = NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);
        return uint256(liquidity);
    }

    function distributeRewards(uint256 amount) external {
        require(block.timestamp >= periodEnd, "Current period is still active");
        staiKToken.transferFrom(msg.sender, address(this), amount);
        rewardPool = rewardPool.add(amount);
        periodEnd = block.timestamp.add(REWARD_PERIOD);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
