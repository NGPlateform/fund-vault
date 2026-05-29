// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "../BaseTest.sol";

/// @notice 关键不变量（单次断言风格；可后续升级为 stateful invariant runs）：
///   - target weight 总和 ≤ 10_000
///   - allocation.totalAssets() 非负且等于 idle + sum(strategy.totalAssets)
///   - reserve cap 限制：注入后不超 cap
///   - rebalance 不破坏资产守恒
contract FundInvariantsTest is BaseTest {
    function test_TargetSum_LessOrEqual10000() public view {
        assertLe(allocation.targetSumBps(), 10_000);
    }

    function test_TotalAssets_EqualsBreakdown() public {
        vm.prank(alice);
        sub.subscribe(50_000 * USDC_UNIT);
        vm.prank(gov);
        allocation.rebalance();

        uint256 ta = allocation.totalAssets();
        (uint256 idle, ) = vault.balanceBreakdown();
        uint256 stratBal = strat.totalAssets();
        assertEq(ta, idle + stratBal);
    }

    function test_RebalanceConserves() public {
        vm.prank(alice);
        sub.subscribe(100_000 * USDC_UNIT);
        uint256 before_ = allocation.totalAssets();
        vm.prank(gov);
        allocation.rebalance();
        uint256 after_ = allocation.totalAssets();
        // 再平衡不应改变总资产（无费率介入）
        assertEq(before_, after_);
    }

    function test_Lockup_BlocksRedeem() public {
        vm.prank(alice);
        sub.subscribe(10_000 * USDC_UNIT);
        _postNAV(1, 1e18);
        vm.prank(alice);
        vm.expectRevert();
        red.redeem(1_000 * USDC_UNIT);
    }

    function test_EpochNonReentry() public {
        vm.prank(alice);
        sub.subscribe(100_000 * USDC_UNIT);
        vm.prank(gov);
        allocation.rebalance();
        uint256 baseline = allocation.totalAssets();
        vm.prank(gov);
        dailyTick.setLastAum(baseline);

        uint256 aum = allocation.totalAssets();
        uint256 nav = (aum * 1e18) / shareToken.totalSupply();
        _postNAV(1, nav);
        skip(24 hours);
        dailyTick.executeDailyTick(1, bytes32(uint256(11)));

        // 再次发布 epoch 1 应失败（已发布）
        _postNAV(2, nav); // epoch 2 OK
        skip(24 hours);
        dailyTick.executeDailyTick(2, bytes32(uint256(22)));

        // 试图重新对 epoch 1 调用应失败（lastEpoch 检查）
        vm.expectRevert();
        dailyTick.executeDailyTick(1, bytes32(uint256(33)));
    }
}
