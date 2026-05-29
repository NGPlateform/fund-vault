// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFundVault} from "../interfaces/IFundVault.sol";
import {IAllocationManager} from "../interfaces/IAllocationManager.sol";
import {INAVOracle} from "../interfaces/INAVOracle.sol";
import {ISettlementPolicy} from "../interfaces/ISettlementPolicy.sol";
import {IReserveFund} from "../interfaces/IReserveFund.sol";
import {IDividendManager} from "../interfaces/IDividendManager.sol";
import {IEmergencyController} from "../interfaces/IEmergencyController.sol";

/// @title DailyTick — 每日结算协调
/// @notice 任何 EOA 可调（受时间窗口与 NAV 已发布 gating）。完整流程：
///         1) 读 AUM、储备金、上一 lastAum，计算 pnl
///         2) Policy.settle() 得 plan
///         3) 注入/支取储备金
///         4) Vault → DividendManager 推入 totalDividend
///         5) DividendManager.publishRoot(epoch, root, total)
contract DailyTick is Ownable, ReentrancyGuard {
    IFundVault public immutable vault;
    IAllocationManager public immutable allocation;
    INAVOracle public immutable navOracle;
    IReserveFund public immutable reserve;
    IDividendManager public immutable dividendManager;
    IEmergencyController public immutable emergency;

    ISettlementPolicy public policy;

    uint256 public lastAum;
    uint64 public lastEpoch;
    uint64 public minIntervalSecs = 23 hours; // 略宽松，留 keeper 调用窗口
    uint64 public lastTickAt;

    event PolicySet(address indexed policy, bytes32 policyId);
    event TickExecuted(uint64 indexed epoch, int256 pnl, uint256 aum, uint256 totalDividend, bytes32 root);

    error EmergencyPause();
    error TooEarly();
    error NAVNotPosted();
    error EpochOutOfOrder();

    constructor(
        address owner_,
        address vault_,
        address allocation_,
        address navOracle_,
        address reserve_,
        address dividendManager_,
        address emergency_,
        address policy_
    ) Ownable(owner_) {
        vault = IFundVault(vault_);
        allocation = IAllocationManager(allocation_);
        navOracle = INAVOracle(navOracle_);
        reserve = IReserveFund(reserve_);
        dividendManager = IDividendManager(dividendManager_);
        emergency = IEmergencyController(emergency_);
        policy = ISettlementPolicy(policy_);
        emit PolicySet(policy_, ISettlementPolicy(policy_).policyId());
    }

    function setPolicy(address policy_) external onlyOwner {
        policy = ISettlementPolicy(policy_);
        emit PolicySet(policy_, ISettlementPolicy(policy_).policyId());
    }

    function setMinIntervalSecs(uint64 secs) external onlyOwner {
        minIntervalSecs = secs;
    }

    function setLastAum(uint256 v) external onlyOwner {
        lastAum = v;
    }

    /// @notice 一日一次的结算入口。
    /// @param epoch       本次结算的 epoch（与 NAVOracle 对齐）
    /// @param merkleRoot  全持有人当日分红的 Merkle 根（链下计算）
    function executeDailyTick(uint64 epoch, bytes32 merkleRoot) external nonReentrant {
        if (emergency.isPaused()) revert EmergencyPause();
        if (block.timestamp < lastTickAt + minIntervalSecs) revert TooEarly();
        if (!navOracle.epochPosted(epoch)) revert NAVNotPosted();
        if (lastEpoch != 0 && epoch <= lastEpoch) revert EpochOutOfOrder();

        uint256 aum = allocation.totalAssets();
        int256 pnl = int256(aum) - int256(lastAum);
        uint256 reserveBal = reserve.balance();

        ISettlementPolicy.DividendPlan memory plan =
            policy.settle(epoch, pnl, aum, reserveBal);

        // 1) 储备注入（vault → reserve）
        if (plan.reserveInjected > 0) {
            vault.requestPayout(address(reserve), plan.reserveInjected);
        }
        // 2) 储备支取（reserve → vault）— 用于兜底分红
        if (plan.reserveDrawn > 0) {
            reserve.draw(plan.reserveDrawn, address(vault));
        }
        // 3) 分红资金 vault → DividendManager
        if (plan.totalDividend > 0) {
            vault.requestPayout(address(dividendManager), plan.totalDividend);
        }
        // 4) 发布 Merkle 根
        dividendManager.publishRoot(epoch, merkleRoot, plan.totalDividend);

        // 5) 更新 lastAum：当日 PnL 留 NAV 的部分 + 减去分红流出 + 储备增量
        // 实际 vault+strategy 总资产 = aum - reserveInjected + reserveDrawn - totalDividend
        // 但作为基准，下一轮 PnL 与该值比较：
        lastAum = uint256(int256(aum) + int256(plan.reserveDrawn) - int256(plan.reserveInjected) - int256(plan.totalDividend));
        lastEpoch = epoch;
        lastTickAt = uint64(block.timestamp);

        emit TickExecuted(epoch, pnl, aum, plan.totalDividend, merkleRoot);
    }
}
