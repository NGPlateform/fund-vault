// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IFundVault — 基金资产唯一链上托管金库
/// @notice 只接收/出付一种 baseAsset（如 USDC）。出金需经 spender 授权（SubscriptionManager、
///         RedemptionManager、DailyTick 等核心合约）。链下交易系统经 AllocationManager → IStrategy
///         划拨/归还资金。
interface IFundVault {
    event PayoutRequested(address indexed spender, address indexed to, uint256 amount);
    event DeployedToStrategy(address indexed strategy, uint256 amount);
    event ReturnedFromStrategy(address indexed strategy, uint256 amount);
    event SpenderAuthorized(address indexed spender, bool authorized);

    /// @notice 授权 spender 向 `to` 出金 `amount` baseAsset。仅授权合约可调。
    function requestPayout(address to, uint256 amount) external;

    /// @notice 由 AllocationManager 调用，向某策略划拨资金；记录 deployed[strategy] += amount。
    function deployToStrategy(address strategy, uint256 amount) external;

    /// @notice 由 AllocationManager 调用，从某策略归还资金（本金 + 利润）。
    function returnFromStrategy(address strategy, uint256 amount) external;

    /// @notice 基础资产地址。
    function baseAsset() external view returns (address);

    /// @notice 某策略已划拨但未归还的数量。
    function deployedTo(address strategy) external view returns (uint256);

    /// @notice (idle, deployed) 拆分。idle = 金库内可动用；deployed = 划拨给策略的总和。
    function balanceBreakdown() external view returns (uint256 idle, uint256 deployed);
}
