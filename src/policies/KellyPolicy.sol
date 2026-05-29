// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISettlementPolicy} from "../interfaces/ISettlementPolicy.sol";
import {DailyMath} from "../libraries/DailyMath.sol";

/// @title KellyPolicy — F* Capital 凯利策略
/// @notice 不承诺固定分红（避开"保收益"语义）。盈利日的可分配比例由 fractional Kelly 决定：
///         disbursableBps = kellyFractionBps（如 2500 = 1/4 Kelly），其余分别留 NAV 与储备。
///         亏损日：无分红动作。储备金低于底线时浮动分红暂停。
contract KellyPolicy is ISettlementPolicy, Ownable {
    bytes32 public constant override policyId = keccak256("KELLY_V1");

    struct Params {
        uint16 kellyFractionBps;   // 2500 = 1/4 Kelly（pure float dividend portion of profit）
        uint16 reserveInjectBps;   // 1500 = 15% of profit
        uint16 toNAVBps;           // 6000 = 60% of profit
        uint16 reserveCapBps;      // 2500
        uint16 reserveFloorBps;    // 500
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
        if (uint256(p.kellyFractionBps) + p.reserveInjectBps + p.toNAVBps != 10_000) revert InvalidParams();
        if (p.reserveCapBps > 5_000 || p.reserveFloorBps > p.reserveCapBps) revert InvalidParams();
        params = p;
    }

    function settle(uint64 /*epoch*/, int256 pnl, uint256 aum, uint256 reserveBal)
        external
        view
        returns (DividendPlan memory plan)
    {
        Params memory p = params;
        plan.floatSuspended = (reserveBal < (aum * p.reserveFloorBps) / 10_000);
        plan.fixedDividend = 0;

        if (pnl <= 0) {
            // 亏损日：什么都不做（无承诺分红，因此无需储备兜底）
            return plan;
        }

        uint256 profit = uint256(pnl);
        uint256 floatAmt = plan.floatSuspended ? 0 : DailyMath.mulBps(profit, p.kellyFractionBps);
        uint256 navAmt = DailyMath.mulBps(profit, p.toNAVBps);
        uint256 injAmt = DailyMath.mulBps(profit, p.reserveInjectBps);

        // cap 上限
        uint256 cap = (aum * p.reserveCapBps) / 10_000;
        uint256 room = cap > reserveBal ? cap - reserveBal : 0;
        if (injAmt > room) {
            navAmt += (injAmt - room);
            injAmt = room;
        }
        if (plan.floatSuspended) {
            // 暂停时把本应做浮动的部分转 NAV
            navAmt += DailyMath.mulBps(profit, p.kellyFractionBps);
        }

        plan.floatDividend = floatAmt;
        plan.toNAV = navAmt;
        plan.reserveInjected = injAmt;
        plan.totalDividend = floatAmt;
    }
}
