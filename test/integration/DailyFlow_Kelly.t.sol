// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseTest.sol";

/// @notice Kelly Policy 实例化下的每日流程：盈利日有 dividend、亏损日完全静默。
contract DailyFlow_Kelly_Test is BaseTest {
    function setUp() public override {
        super.setUp();
        // 切换 DailyTick 的 Policy 到 KellyPolicy
        vm.prank(gov);
        dailyTick.setPolicy(address(kelly));
    }

    function _setupAndSubscribe() internal {
        vm.prank(alice);
        sub.subscribe(100_000 * USDC_UNIT);
        vm.prank(gov);
        allocation.rebalance();
        uint256 baseline = allocation.totalAssets();
        vm.prank(gov);
        dailyTick.setLastAum(baseline);
    }

    function test_KellyProfitDay_DividendIsKellyFraction() public {
        _setupAndSubscribe();
        // Reserve 20% AUM
        usdc.mint(gov, 20_000 * USDC_UNIT);
        vm.prank(gov);
        usdc.transfer(address(reserve), 20_000 * USDC_UNIT);

        // Strategy profit = 1000 USDC
        vm.startPrank(gov);
        usdc.mint(gov, 1_000 * USDC_UNIT);
        usdc.approve(address(strat), 1_000 * USDC_UNIT);
        strat.setPnL(int256(1_000 * USDC_UNIT));
        vm.stopPrank();

        uint256 aum = allocation.totalAssets();
        uint256 nav = (aum * 1e18) / shareToken.totalSupply();
        _postNAV(1, nav);
        skip(24 hours);

        dailyTick.executeDailyTick(1, bytes32(uint256(7)));

        // Kelly: float = 25% of 1000 = 250 USDC; reserve += 15%; nav += 60%
        // fixed = 0
        assertEq(dividendManager.totalAt(1), 250 * USDC_UNIT);
    }

    function test_KellyLossDay_NoDividend() public {
        _setupAndSubscribe();
        usdc.mint(gov, 20_000 * USDC_UNIT);
        vm.prank(gov);
        usdc.transfer(address(reserve), 20_000 * USDC_UNIT);

        vm.prank(gov);
        strat.setPnL(-int256(500 * USDC_UNIT));

        uint256 aum = allocation.totalAssets();
        uint256 nav = (aum * 1e18) / shareToken.totalSupply();
        _postNAV(1, nav);
        skip(24 hours);

        uint256 reserveBefore = reserve.balance();
        dailyTick.executeDailyTick(1, bytes32(uint256(8)));

        // 亏损日：无分红、无储备动作
        assertEq(dividendManager.totalAt(1), 0);
        assertEq(reserve.balance(), reserveBefore);
    }
}
