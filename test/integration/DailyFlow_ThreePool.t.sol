// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseTest.sol";

/// @notice 完整每日流程：申购 → 策略入金 → 注入储备 → 策略产生 PnL → DailyTick → 分红根发布
contract DailyFlow_ThreePool_Test is BaseTest {
    function _setupAndSubscribe() internal {
        // Alice 申购 100,000 USDC（高于 minSubscription 1,000）
        vm.prank(alice);
        sub.subscribe(100_000 * USDC_UNIT);
        // 划拨给唯一策略
        vm.prank(gov);
        allocation.rebalance();
        // 锚定基准 AUM：申购完成后总资产作为下一轮 PnL 基准
        uint256 baselineAum = allocation.totalAssets();
        vm.prank(gov);
        dailyTick.setLastAum(baselineAum);
    }

    function test_ProfitDay_DividendAndReserve() public {
        _setupAndSubscribe();
        // 预先注入储备金到 25% AUM
        usdc.mint(gov, 25_000 * USDC_UNIT);
        vm.prank(gov);
        usdc.transfer(address(reserve), 25_000 * USDC_UNIT);

        // Mock 策略产生 1000 USDC 盈利
        vm.startPrank(gov);
        usdc.mint(gov, 1_000 * USDC_UNIT);
        usdc.approve(address(strat), 1_000 * USDC_UNIT);
        strat.setPnL(int256(1_000 * USDC_UNIT));
        vm.stopPrank();

        // 发布 NAV
        uint256 aum = allocation.totalAssets();
        // NAV = aum * 1e18 / supply
        uint256 nav = (aum * 1e18) / shareToken.totalSupply();
        _postNAV(1, nav);

        // 推进时间，执行 daily tick
        skip(24 hours);
        bytes32 root = bytes32(uint256(1));
        uint256 reserveBefore = reserve.balance();
        uint256 dmBefore = usdc.balanceOf(address(dividendManager));

        dailyTick.executeDailyTick(1, root);

        // fixedDividend ≈ 100_000 * 6% / 365 ≈ 16.43 USDC
        // floatDividend = (1000 - 16.43) * 30% ≈ 295
        // reserveInjected = (1000 - 16.43) * 10% ≈ 98
        // 但 reserve 已到 cap (25%) → injected 实际为 0（截断）
        ISettlementPolicy.DividendPlan memory plan =
            threePool.settle(1, int256(1000 * USDC_UNIT), aum, reserveBefore);

        // 分红资金转入 DividendManager
        assertEq(usdc.balanceOf(address(dividendManager)) - dmBefore, plan.totalDividend);
        // 储备金按计划变化
        assertEq(reserve.balance(), reserveBefore + plan.reserveInjected - plan.reserveDrawn);
        // 根已发布
        assertEq(dividendManager.rootOf(1), root);
        assertEq(dividendManager.totalAt(1), plan.totalDividend);
    }

    function test_LossDay_ReserveDrawn() public {
        _setupAndSubscribe();
        // 储备 20% AUM
        usdc.mint(gov, 20_000 * USDC_UNIT);
        vm.prank(gov);
        usdc.transfer(address(reserve), 20_000 * USDC_UNIT);

        // 策略亏损 500 USDC
        vm.prank(gov);
        strat.setPnL(-int256(500 * USDC_UNIT));

        uint256 aum = allocation.totalAssets();
        uint256 nav = (aum * 1e18) / shareToken.totalSupply();
        _postNAV(1, nav);

        skip(24 hours);
        uint256 reserveBefore = reserve.balance();
        uint256 aumAtTick = allocation.totalAssets();
        dailyTick.executeDailyTick(1, bytes32(uint256(2)));

        // 固定分红 = aum * 6% / 365 由储备金兜底（aum 为亏损后实际值）
        uint256 fixed_ = (aumAtTick * 600) / 10_000 / 365;
        assertApproxEqAbs(reserveBefore - reserve.balance(), fixed_, 2);
        assertEq(dividendManager.totalAt(1), fixed_);
    }

    function test_TooEarly_Reverts() public {
        _setupAndSubscribe();
        uint256 aum = allocation.totalAssets();
        uint256 nav = (aum * 1e18) / shareToken.totalSupply();
        _postNAV(1, nav);
        dailyTick.executeDailyTick(1, bytes32(uint256(1)));
        // 立刻再次调用应失败（minInterval 未到）
        // 但先发 NAV epoch 2
        _postNAV(2, nav);
        vm.expectRevert();
        dailyTick.executeDailyTick(2, bytes32(uint256(2)));
    }
}
