// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IStrategy — 策略适配器接口
/// @notice 把链下交易系统抽象为一个"账户"。Vault 通过 deposit/withdraw 转账；totalAssets() 报告本策略
///         当前账面价值（含未归还本金 + 浮动盈亏）。具体策略实现可对接 CEX 托管、DeFi 协议、
///         离线签名账户等。
interface IStrategy {
    /// @notice 接收资金并入账（baseAsset 由 vault 推送）。
    function deposit(uint256 amount) external;

    /// @notice 申请提取资金，转回 FundVault。
    function withdraw(uint256 amount) external;

    /// @notice 当前本策略账面总价值（含本金 + 盈亏），以 baseAsset 计价。
    function totalAssets() external view returns (uint256);

    function baseAsset() external view returns (address);
}
