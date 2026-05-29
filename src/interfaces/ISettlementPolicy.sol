// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ISettlementPolicy — 每日结算策略（关键抽象）
/// @notice 把"PnL → 分红 / 净值留存 / 储备金动作"的逻辑做成可插拔的纯函数。
///         每只基金通过部署不同的 Policy 来实现完全不同的分红与资金管理哲学。
interface ISettlementPolicy {
    /// @dev 由 settle() 产出的结算计划，由 DailyTick 协调执行。
    struct DividendPlan {
        uint256 fixedDividend;   // 固定分红（基础部分；Kelly 模式下可为 0）
        uint256 floatDividend;   // 浮动分红（盈利日抽成）
        uint256 totalDividend;   // = fixedDividend + floatDividend
        uint256 toNAV;           // 留存进净值的金额
        uint256 reserveInjected; // 注入储备金的金额
        uint256 reserveDrawn;    // 从储备金支取兜底的金额
        bool    floatSuspended;  // 是否因储备金不足而暂停浮动分红
        bytes   policyData;      // Policy 私有数据（可选）
    }

    /// @notice 由 DailyTick 调用，返回当日结算计划（纯计算，不修改状态）。
    /// @param epoch       第几个结算周期（自 epoch 0 起递增）
    /// @param pnl         当日盈亏（可负），单位：基础资产最小单位（如 USDC = 1e6）
    /// @param aum         当前管理资产规模（结算前的 AUM）
    /// @param reserveBal  当前储备金余额
    /// @return plan       结算计划
    function settle(uint64 epoch, int256 pnl, uint256 aum, uint256 reserveBal)
        external
        view
        returns (DividendPlan memory plan);

    /// @notice Policy 唯一标识（如 keccak256("THREE_POOL_V1")）
    function policyId() external view returns (bytes32);
}
