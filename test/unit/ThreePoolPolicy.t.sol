// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ThreePoolPolicy} from "src/policies/ThreePoolPolicy.sol";
import {ISettlementPolicy} from "src/interfaces/ISettlementPolicy.sol";

contract ThreePoolPolicyTest is Test {
    ThreePoolPolicy public p;
    address gov = address(0x1);
    uint256 constant USDC = 1e6;

    function setUp() public {
        p = new ThreePoolPolicy(
            gov,
            ThreePoolPolicy.Params({
                fixedYieldBpsYear: 600,
                floatBps: 3000,
                toNAVBps: 6000,
                reserveInjectBps: 1000,
                reserveCapBps: 2500,
                reserveFloorBps: 500
            })
        );
    }

    function test_PolicyId() public view {
        assertEq(p.policyId(), keccak256("THREE_POOL_V1"));
    }

    function test_FixedDividend_AnnualRate() public view {
        // AUM = 20_000_000 USDC; 6%/yr / 365 ≈ 3287.67 USDC/day
        uint256 aum = 20_000_000 * USDC;
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, int256(0), aum, aum / 10);
        // pnl = 0 → fixedDividend 全部由储备金兜底
        uint256 expectedDaily = (aum * 600) / 10_000 / 365;
        assertEq(plan.fixedDividend, expectedDaily);
        assertEq(plan.reserveDrawn, expectedDaily);
        assertEq(plan.floatDividend, 0);
    }

    function test_ProfitDay_ThreeWaySplit() public view {
        uint256 aum = 20_000_000 * USDC;
        int256 pnl = int256(10_000 * USDC); // 1 万 USDC 盈利
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, pnl, aum, aum * 20 / 100);
        // 固定 ≈ 3287.67；profit 剩 ≈ 6712；按 30/60/10 分配
        uint256 fixed_ = (aum * 600) / 10_000 / 365;
        uint256 remain = uint256(pnl) - fixed_;
        assertEq(plan.fixedDividend, fixed_);
        assertEq(plan.floatDividend, (remain * 3000) / 10_000);
        assertEq(plan.toNAV, (remain * 6000) / 10_000);
        assertEq(plan.reserveInjected, (remain * 1000) / 10_000);
        assertEq(plan.totalDividend, plan.fixedDividend + plan.floatDividend);
        assertFalse(plan.floatSuspended);
    }

    function test_LossDay_DrawFromReserve() public view {
        uint256 aum = 20_000_000 * USDC;
        int256 pnl = -int256(5_000 * USDC);
        uint256 reserveBal = aum * 20 / 100;
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, pnl, aum, reserveBal);
        uint256 fixed_ = (aum * 600) / 10_000 / 365;
        assertEq(plan.fixedDividend, fixed_);
        assertEq(plan.reserveDrawn, fixed_);
        assertEq(plan.floatDividend, 0);
        assertEq(plan.reserveInjected, 0);
    }

    function test_LowReserve_SuspendFloat() public view {
        uint256 aum = 20_000_000 * USDC;
        int256 pnl = int256(10_000 * USDC);
        uint256 reserveBal = aum * 4 / 100; // 4% < 5% floor
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, pnl, aum, reserveBal);
        assertTrue(plan.floatSuspended);
        assertEq(plan.floatDividend, 0);
        // 30% 应转入 NAV
        uint256 fixed_ = (aum * 600) / 10_000 / 365;
        uint256 remain = uint256(pnl) - fixed_;
        // toNAV = 60% + 30%
        assertEq(plan.toNAV, (remain * 6000) / 10_000 + (remain * 3000) / 10_000);
    }

    function test_ReserveCap_RedirectToNAV() public view {
        uint256 aum = 20_000_000 * USDC;
        int256 pnl = int256(10_000 * USDC);
        uint256 reserveBal = aum * 25 / 100; // 25% 已到 cap
        ISettlementPolicy.DividendPlan memory plan = p.settle(0, pnl, aum, reserveBal);
        // reserveInjected 应被截断为 0；溢出转入 NAV
        assertEq(plan.reserveInjected, 0);
    }

    function test_RevertOnInvalidParams() public {
        ThreePoolPolicy.Params memory bad = ThreePoolPolicy.Params({
            fixedYieldBpsYear: 600,
            floatBps: 3000,
            toNAVBps: 5000, // 30 + 50 + 10 = 90 ≠ 100
            reserveInjectBps: 1000,
            reserveCapBps: 2500,
            reserveFloorBps: 500
        });
        vm.expectRevert();
        new ThreePoolPolicy(gov, bad);
    }
}
