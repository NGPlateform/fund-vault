// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISubscriptionManager} from "../interfaces/ISubscriptionManager.sol";
import {IKYCRegistry} from "../interfaces/IKYCRegistry.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {INAVOracle} from "../interfaces/INAVOracle.sol";
import {IEmergencyController} from "../interfaces/IEmergencyController.sol";

/// @title SubscriptionManager — 申购
contract SubscriptionManager is ISubscriptionManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant NAV_SCALE = 1e18;

    IKYCRegistry public immutable kyc;
    IShareToken public immutable shareToken;
    INAVOracle public immutable navOracle;
    IEmergencyController public immutable emergency;
    IERC20 public immutable baseAsset;
    address public immutable vault; // FundVault

    uint256 public override minSubscription;
    uint32 public override lockupSecs;

    mapping(address => Deposit[]) internal _deposits;

    error NotKYC();
    error BelowMin();
    error NoNAV();
    error Paused();
    error ZeroShares();

    constructor(
        address owner_,
        address kyc_,
        address shareToken_,
        address navOracle_,
        address emergency_,
        address baseAsset_,
        address vault_,
        uint256 minSubscription_,
        uint32 lockupSecs_
    ) Ownable(owner_) {
        kyc = IKYCRegistry(kyc_);
        shareToken = IShareToken(shareToken_);
        navOracle = INAVOracle(navOracle_);
        emergency = IEmergencyController(emergency_);
        baseAsset = IERC20(baseAsset_);
        vault = vault_;
        minSubscription = minSubscription_;
        lockupSecs = lockupSecs_;
        emit MinSubscriptionSet(minSubscription_);
        emit LockupSet(lockupSecs_);
    }

    function setMinSubscription(uint256 amount) external onlyOwner {
        minSubscription = amount;
        emit MinSubscriptionSet(amount);
    }

    function setLockupSecs(uint32 secs) external onlyOwner {
        lockupSecs = secs;
        emit LockupSet(secs);
    }

    function subscribe(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (emergency.isPaused()) revert Paused();
        if (!kyc.isApproved(msg.sender)) revert NotKYC();
        if (amount < minSubscription) revert BelowMin();

        // 拉资产到 vault
        baseAsset.safeTransferFrom(msg.sender, vault, amount);

        uint256 nav;
        uint256 supply = shareToken.totalSupply();
        if (supply == 0) {
            shares = amount; // 1:1 bootstrap（同 decimals）
            nav = NAV_SCALE;
        } else {
            INAVOracle.NAVRecord memory rec = navOracle.latest();
            if (rec.nav == 0) revert NoNAV();
            nav = rec.nav;
            shares = (amount * NAV_SCALE) / nav;
        }
        if (shares == 0) revert ZeroShares();

        uint64 unlockAt = uint64(block.timestamp) + lockupSecs;
        _deposits[msg.sender].push(
            Deposit({
                amount: amount,
                sharesMinted: shares,
                depositedAt: uint64(block.timestamp),
                unlockAt: unlockAt
            })
        );
        shareToken.mint(msg.sender, shares);
        emit Subscribed(msg.sender, amount, shares, nav, unlockAt);
    }

    /// @notice 由 RedemptionManager 调用：按 FIFO 扣减未锁定的 deposits 中的份额。
    function consumeUnlocked(address account, uint256 shares) external returns (bool) {
        // 仅 Owner 设置的特许调用方可调；保持简单，要求调用方是 owner 在初始化时记录的 redeemer
        require(msg.sender == redemptionManager, "SM: not redeemer");
        return _consume(account, shares);
    }

    address public redemptionManager;
    function setRedemptionManager(address r) external onlyOwner {
        redemptionManager = r;
    }

    function _consume(address account, uint256 shares) internal returns (bool) {
        Deposit[] storage arr = _deposits[account];
        uint256 remaining = shares;
        uint256 i;
        uint256 n = arr.length;
        for (; i < n && remaining > 0; ++i) {
            Deposit storage d = arr[i];
            if (d.unlockAt > block.timestamp || d.sharesMinted == 0) continue;
            uint256 take = d.sharesMinted < remaining ? d.sharesMinted : remaining;
            d.sharesMinted -= take;
            remaining -= take;
        }
        return remaining == 0;
    }

    function depositsOf(address account) external view returns (Deposit[] memory) {
        return _deposits[account];
    }

    function freeShares(address account) public view returns (uint256 total) {
        Deposit[] storage arr = _deposits[account];
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i].unlockAt <= block.timestamp) total += arr[i].sharesMinted;
        }
    }

    function lockedShares(address account) external view returns (uint256 total) {
        Deposit[] storage arr = _deposits[account];
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i].unlockAt > block.timestamp) total += arr[i].sharesMinted;
        }
    }

    /// @notice 已持有最久（首次申购）距今天数；用于阶梯赎回费。
    function holdingDays(address account) external view returns (uint32) {
        Deposit[] storage arr = _deposits[account];
        if (arr.length == 0) return 0;
        uint64 oldest = arr[0].depositedAt;
        for (uint256 i = 1; i < arr.length; ++i) {
            if (arr[i].depositedAt < oldest) oldest = arr[i].depositedAt;
        }
        return uint32((block.timestamp - oldest) / 1 days);
    }
}
