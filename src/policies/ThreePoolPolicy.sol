// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISettlementPolicy} from "../interfaces/ISettlementPolicy.sol";
import {DailyMath} from "../libraries/DailyMath.sol";

/// @title ThreePoolPolicy — QDFI 三池机制
/// @notice 等价于 qdf-contracts/PoolManager 的结算逻辑：
///         - fixedDividend = AUM * fixedYieldBpsYear / 365（不足由储备兜底）
///         - 盈利日：profit 按 floatBps + reserveInjectBps + toNAVBps（合 10000）三路分配
///         - 亏损日：fixedDividend 由储备兜底；不可兜底则少发并 floatSuspended
///         - reserveCap = AUM * reserveCapBps 上限；reserveBal < AUM * floorBps 则 floatSuspended
contract ThreePoolPolicy is ISettlementPolicy, Ownable {
    bytes32 public constant override policyId = keccak256("THREE_POOL_V1");

    struct Params {
        uint16 fixedYieldBpsYear;  // 600 = 6%/yr
        uint16 floatBps;           // 3000 = 30% of profit
        uint16 toNAVBps;           // 6000 = 60% of profit (留 NAV)
        uint16 reserveInjectBps;   // 1000 = 10% of profit (注入储备)
        uint16 reserveCapBps;      // 2500 = 25% AUM 封顶
        uint16 reserveFloorBps;    // 500  = 5%  AUM 底线
    }

    Params public params;

    error InvalidParams();

    constructor(address owner_, Params memory p) Ownable(owner_) {
        _setParams(p);
    }

    function setParams(Params calldata p) external onlyOwner {
        _setParams(p);
    }

    function _setParams(Params memory p) internal {
        // 盈利日三路必须凑成 10000
        if (uint256(p.floatBps) + p.toNAVBps + p.reserveInjectBps != 10_000) revert InvalidParams();
        if (p.fixedYieldBpsYear > 5_000) revert InvalidParams(); // 上限 50%/yr 防呆
        if (p.reserveCapBps > 5_000 || p.reserveFloorBps > p.reserveCapBps) revert InvalidParams();
        params = p;
    }

    function settle(uint64 /*epoch*/, int256 pnl, uint256 aum, uint256 reserveBal)
        external
        view
        returns (DividendPlan memory plan)
    {
        Params memory p = params;
        uint256 fixedAmt = DailyMath.dailyFromAnnualBps(aum, p.fixedYieldBpsYear);

        // float 暂停判断
        bool suspend = (reserveBal < (aum * p.reserveFloorBps) / 10_000);
        plan.floatSuspended = suspend;

        if (pnl >= 0) {
            uint256 profit = uint256(pnl);
            // 固定分红：先取 profit 顶上限，不够再走储备 / 兜底
            uint256 fromProfitForFixed = profit > fixedAmt ? fixedAmt : profit;
            uint256 profitRemain = profit - fromProfitForFixed;
            uint256 fromReserveForFixed;
            if (fromProfitForFixed < fixedAmt) {
                uint256 short = fixedAmt - fromProfitForFixed;
                fromReserveForFixed = short > reserveBal ? reserveBal : short;
                plan.reserveDrawn += fromReserveForFixed;
            }
            plan.fixedDividend = fromProfitForFixed + fromReserveForFixed;

            // 剩余 profit 三路分配
            uint256 floatAmt = suspend ? 0 : DailyMath.mulBps(profitRemain, p.floatBps);
            uint256 navAmt = DailyMath.mulBps(profitRemain, p.toNAVBps);
            uint256 injAmt = DailyMath.mulBps(profitRemain, p.reserveInjectBps);

            // 注入储备需尊重 cap
            uint256 cap = (aum * p.reserveCapBps) / 10_000;
            uint256 reserveAfterDraw = reserveBal - plan.reserveDrawn;
            uint256 room = cap > reserveAfterDraw ? cap - reserveAfterDraw : 0;
            if (injAmt > room) {
                navAmt += (injAmt - room); // 溢出转入净值
                injAmt = room;
            }
            plan.floatDividend = floatAmt;
            plan.toNAV = navAmt;
            plan.reserveInjected = injAmt;
            // float 暂停时把本应分红的部分也转入净值
            if (suspend) plan.toNAV += DailyMath.mulBps(profitRemain, p.floatBps);
        } else {
            // 亏损日：浮动 = 0；固定分红由储备兜底
            uint256 short = fixedAmt > reserveBal ? reserveBal : fixedAmt;
            plan.fixedDividend = short;
            plan.reserveDrawn = short;
            plan.floatDividend = 0;
            plan.toNAV = 0;
            plan.reserveInjected = 0;
        }

        plan.totalDividend = plan.fixedDividend + plan.floatDividend;
    }
}
