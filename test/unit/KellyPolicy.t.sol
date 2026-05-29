// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {KellyPolicy} from "src/policies/KellyPolicy.sol";
import {ISettlementPolicy} from "src/interfaces/ISettlementPolicy.sol";

contract KellyPolicyTest is Test {
    KellyPolicy public p;
    address gov = address(0x1);
    uint256 constant USDC = 1e6;

    function setUp() public {
        p = new KellyPolicy(
            gov,
            KellyPolicy.Params({
                kellyFractionBps: 2500,
                reserveInjectBps: 1500,
                toNAVBps: 6000,
                reserveCapBps: 2500,
                reserveFloorBps: 500
            })
        );
    }

    function test_PolicyId() public view {
        assertEq(p.policyId(), keccak256("KELLY_V1"));
    }

    function test_LossDay_DoesNothing() public view {
        uint256 aum = 20_000_000 * USDC;
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, -int256(10_000 * USDC), aum, aum * 20 / 100);
        // 不承诺固定分红 → 亏损日全 0
        assertEq(plan.fixedDividend, 0);
        assertEq(plan.floatDividend, 0);
        assertEq(plan.reserveInjected, 0);
        assertEq(plan.reserveDrawn, 0);
        assertEq(plan.totalDividend, 0);
        assertFalse(plan.floatSuspended);
    }

    function test_ProfitDay_KellyFractionSplit() public view {
        uint256 aum = 20_000_000 * USDC;
        int256 pnl = int256(10_000 * USDC);
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, pnl, aum, aum * 20 / 100);
        // 25/15/60 分
        assertEq(plan.floatDividend, (uint256(pnl) * 2500) / 10_000);
        assertEq(plan.reserveInjected, (uint256(pnl) * 1500) / 10_000);
        assertEq(plan.toNAV, (uint256(pnl) * 6000) / 10_000);
        assertEq(plan.fixedDividend, 0);
        assertEq(plan.totalDividend, plan.floatDividend);
    }

    function test_LowReserve_SuspendFloat() public view {
        uint256 aum = 20_000_000 * USDC;
        int256 pnl = int256(10_000 * USDC);
        uint256 reserveBal = aum * 4 / 100;
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, pnl, aum, reserveBal);
        assertTrue(plan.floatSuspended);
        assertEq(plan.floatDividend, 0);
        // 25% 应转入 NAV
        assertEq(plan.toNAV, (uint256(pnl) * 6000) / 10_000 + (uint256(pnl) * 2500) / 10_000);
    }
}
