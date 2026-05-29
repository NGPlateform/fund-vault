// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRedemptionManager} from "../interfaces/IRedemptionManager.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {INAVOracle} from "../interfaces/INAVOracle.sol";
import {IFundVault} from "../interfaces/IFundVault.sol";
import {IEmergencyController} from "../interfaces/IEmergencyController.sol";
import {SubscriptionManager} from "./SubscriptionManager.sol";

/// @title RedemptionManager — 赎回
contract RedemptionManager is IRedemptionManager, Ownable, ReentrancyGuard {
    uint256 internal constant NAV_SCALE = 1e18;

    IShareToken public immutable shareToken;
    INAVOracle public immutable navOracle;
    IFundVault public immutable vault;
    IEmergencyController public immutable emergency;
    SubscriptionManager public immutable sub;
    address public immutable reserve;

    struct FeeTier {
        uint32 maxDays; // 持有期 ≤ maxDays 时适用此 BPS（最后一档应为 type(uint32).max）
        uint16 bps;
    }

    FeeTier[] public feeTiers;

    error Paused();
    error NoNAV();
    error InsufficientFreeShares();
    error ZeroShares();

    constructor(
        address owner_,
        address shareToken_,
        address navOracle_,
        address vault_,
        address emergency_,
        address sub_,
        address reserve_
    ) Ownable(owner_) {
        shareToken = IShareToken(shareToken_);
        navOracle = INAVOracle(navOracle_);
        vault = IFundVault(vault_);
        emergency = IEmergencyController(emergency_);
        sub = SubscriptionManager(sub_);
        reserve = reserve_;
    }

    function setFeeTiers(FeeTier[] calldata tiers) external onlyOwner {
        delete feeTiers;
        for (uint256 i = 0; i < tiers.length; ++i) {
            feeTiers.push(tiers[i]);
            emit FeeTierSet(tiers[i].maxDays, tiers[i].bps);
        }
    }

    function _feeBpsFor(uint32 days_) internal view returns (uint16) {
        uint256 n = feeTiers.length;
        for (uint256 i = 0; i < n; ++i) {
            if (days_ <= feeTiers[i].maxDays) return feeTiers[i].bps;
        }
        return n == 0 ? 0 : feeTiers[n - 1].bps;
    }

    function quote(address account, uint256 shares)
        public
        view
        returns (uint256 grossPayout, uint16 feeBps, uint256 feeAmount, uint256 netPayout)
    {
        INAVOracle.NAVRecord memory rec = navOracle.latest();
        require(rec.nav > 0, "RM: no nav");
        grossPayout = (shares * rec.nav) / NAV_SCALE;
        feeBps = _feeBpsFor(sub.holdingDays(account));
        feeAmount = (grossPayout * feeBps) / 10_000;
        netPayout = grossPayout - feeAmount;
    }

    function redeem(uint256 shares) external nonReentrant returns (uint256 netPayout) {
        if (emergency.isPaused()) revert Paused();
        if (shares == 0) revert ZeroShares();
        if (sub.freeShares(msg.sender) < shares) revert InsufficientFreeShares();

        INAVOracle.NAVRecord memory rec = navOracle.latest();
        if (rec.nav == 0) revert NoNAV();

        uint256 gross = (shares * rec.nav) / NAV_SCALE;
        uint16 bps = _feeBpsFor(sub.holdingDays(msg.sender));
        uint256 fee = (gross * bps) / 10_000;
        uint256 net = gross - fee;

        // 标记 deposits 的 shares 已用
        require(sub.consumeUnlocked(msg.sender, shares), "RM: consume");
        // 销毁份额
        shareToken.burn(msg.sender, shares);
        // 出金
        if (net > 0) vault.requestPayout(msg.sender, net);
        if (fee > 0) vault.requestPayout(reserve, fee); // 100% 入储备

        emit Redeemed(msg.sender, shares, gross, bps, fee, rec.nav);
        return net;
    }
}
