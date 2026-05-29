// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllocationManager} from "../interfaces/IAllocationManager.sol";
import {IFundVault} from "../interfaces/IFundVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/// @title AllocationManager — 多策略权重 + 再平衡
/// @notice 注册 N 个策略 + 目标权重（BPS）+ 单策略上限。rebalance() 朝目标权重平准。
///         实际划拨/归还经由 FundVault；本合约只调度。
contract AllocationManager is IAllocationManager, Ownable, ReentrancyGuard {
    IFundVault public immutable vault;
    StrategyInfo[] private _strategies;
    mapping(address => uint256) private _indexOfStrategy; // 1-based; 0 = not present
    uint16 private _targetSum;

    error UnknownStrategy();
    error AlreadyAdded();
    error InvalidBps();
    error CapExceeded();

    constructor(address owner_, address vault_) Ownable(owner_) {
        require(vault_ != address(0), "AM: vault zero");
        vault = IFundVault(vault_);
    }

    function addStrategy(address strategy, uint16 targetBps, uint16 capBps) external onlyOwner {
        if (strategy == address(0)) revert UnknownStrategy();
        if (_indexOfStrategy[strategy] != 0) revert AlreadyAdded();
        if (capBps == 0 || capBps > 10_000) revert InvalidBps();
        if (_targetSum + targetBps > 10_000) revert InvalidBps();
        _strategies.push(StrategyInfo({ strategy: strategy, targetBps: targetBps, capBps: capBps, active: true }));
        _indexOfStrategy[strategy] = _strategies.length;
        _targetSum += targetBps;
        emit StrategyAdded(strategy, targetBps, capBps);
    }

    function updateStrategy(address strategy, uint16 targetBps, uint16 capBps, bool active) external onlyOwner {
        uint256 idx = _indexOfStrategy[strategy];
        if (idx == 0) revert UnknownStrategy();
        if (capBps == 0 || capBps > 10_000) revert InvalidBps();
        StrategyInfo storage s = _strategies[idx - 1];
        uint16 newSum = _targetSum + targetBps - s.targetBps;
        if (newSum > 10_000) revert InvalidBps();
        _targetSum = newSum;
        s.targetBps = targetBps;
        s.capBps = capBps;
        s.active = active;
        emit StrategyUpdated(strategy, targetBps, capBps, active);
    }

    /// @notice 朝目标权重再平衡。从超额策略撤资 → idle → 注资到不足策略。
    function rebalance() external nonReentrant onlyOwner {
        uint256 total = totalAssets();
        emit Rebalanced(total);

        // 第一遍：从超过 target 的策略撤资
        uint256 n = _strategies.length;
        for (uint256 i = 0; i < n; ++i) {
            StrategyInfo storage s = _strategies[i];
            if (!s.active) continue;
            uint256 cur = IStrategy(s.strategy).totalAssets();
            uint256 target = (total * s.targetBps) / 10_000;
            if (cur > target) {
                uint256 over = cur - target;
                IStrategy(s.strategy).withdraw(over);
                vault.returnFromStrategy(s.strategy, over);
            }
        }
        // 第二遍：向不足策略补足
        for (uint256 i = 0; i < n; ++i) {
            StrategyInfo storage s = _strategies[i];
            if (!s.active) continue;
            uint256 cur = IStrategy(s.strategy).totalAssets();
            uint256 target = (total * s.targetBps) / 10_000;
            uint256 cap = (total * s.capBps) / 10_000;
            if (target > cap) target = cap;
            if (cur < target) {
                uint256 under = target - cur;
                // idle 是否足够
                (uint256 idle, ) = vault.balanceBreakdown();
                if (under > idle) under = idle;
                if (under == 0) continue;
                vault.deployToStrategy(s.strategy, under);
                IStrategy(s.strategy).deposit(under);
            }
        }
    }

    function totalAssets() public view returns (uint256) {
        (uint256 idle, ) = vault.balanceBreakdown();
        uint256 sum = idle;
        for (uint256 i = 0; i < _strategies.length; ++i) {
            sum += IStrategy(_strategies[i].strategy).totalAssets();
        }
        return sum;
    }

    function strategyCount() external view returns (uint256) {
        return _strategies.length;
    }

    function strategyAt(uint256 index) external view returns (StrategyInfo memory) {
        return _strategies[index];
    }

    function targetSumBps() external view returns (uint16) {
        return _targetSum;
    }
}
