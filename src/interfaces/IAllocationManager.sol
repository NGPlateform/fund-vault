// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IAllocationManager — 多策略权重与再平衡
/// @notice 注册 N 个 IStrategy 适配器；每个策略有目标权重（BPS，10000 = 100%）+ 单策略上限。
///         rebalance() 按当前 idle 与各策略 totalAssets() 朝目标权重平准。
interface IAllocationManager {
    struct StrategyInfo {
        address strategy;
        uint16  targetBps;     // 目标权重（10000 = 100%）
        uint16  capBps;        // 单策略上限（如 2000 = 20%）
        bool    active;
    }

    event StrategyAdded(address indexed strategy, uint16 targetBps, uint16 capBps);
    event StrategyUpdated(address indexed strategy, uint16 targetBps, uint16 capBps, bool active);
    event Rebalanced(uint256 totalAssets);

    function addStrategy(address strategy, uint16 targetBps, uint16 capBps) external;
    function updateStrategy(address strategy, uint16 targetBps, uint16 capBps, bool active) external;
    function rebalance() external;

    function totalAssets() external view returns (uint256);
    function strategyCount() external view returns (uint256);
    function strategyAt(uint256 index) external view returns (StrategyInfo memory);
    function targetSumBps() external view returns (uint16);
}
