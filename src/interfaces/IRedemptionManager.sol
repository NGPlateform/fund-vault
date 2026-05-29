// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IRedemptionManager — 赎回管理
/// @notice 锁定期校验 → 阶梯赎回费 → 销毁 ShareToken → 推送 baseAsset 到持有人。
///         赎回费 100% 注入 ReserveFund。
interface IRedemptionManager {
    event Redeemed(
        address indexed account,
        uint256 shares,
        uint256 grossPayout,
        uint256 feeBps,
        uint256 feeAmount,
        uint256 navUsed
    );
    event FeeTierSet(uint32 holdingDays, uint16 feeBps);

    function redeem(uint256 shares) external returns (uint256 netPayout);
    function quote(address account, uint256 shares)
        external
        view
        returns (uint256 grossPayout, uint16 feeBps, uint256 feeAmount, uint256 netPayout);
}
