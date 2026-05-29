// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseTest.sol";

contract SubscriptionRedemptionTest is BaseTest {
    function test_Subscribe_BootstrapMintsOneToOne() public {
        vm.prank(alice);
        uint256 shares = sub.subscribe(10_000 * USDC_UNIT);
        assertEq(shares, 10_000 * USDC_UNIT);
        assertEq(shareToken.balanceOf(alice), 10_000 * USDC_UNIT);
        assertEq(sub.lockedShares(alice), 10_000 * USDC_UNIT);
        assertEq(sub.freeShares(alice), 0);
    }

    function test_Subscribe_BelowMinReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        sub.subscribe(500 * USDC_UNIT); // < 1000 minSubscription
    }

    function test_Subscribe_NonKYCReverts() public {
        address mallory = makeAddr("mallory");
        usdc.mint(mallory, 100_000 * USDC_UNIT);
        vm.startPrank(mallory);
        usdc.approve(address(sub), type(uint256).max);
        vm.expectRevert();
        sub.subscribe(10_000 * USDC_UNIT);
        vm.stopPrank();
    }

    function test_LockupEnforced() public {
        vm.prank(alice);
        sub.subscribe(10_000 * USDC_UNIT);
        _postNAV(1, 1e18); // bootstrap nav
        // 锁定期内尝试赎回应失败
        vm.prank(alice);
        vm.expectRevert();
        red.redeem(1_000 * USDC_UNIT);
    }

    function test_RedeemAfterLockup_WithFeeTier() public {
        vm.prank(alice);
        sub.subscribe(10_000 * USDC_UNIT);
        // 锁定期满 30 天 + < 90 天：2% 费率
        skip(35 days);
        _postNAV(1, 1e18);

        uint256 sharesToRedeem = 1_000 * USDC_UNIT;
        (uint256 gross, uint16 feeBps, uint256 fee, uint256 net) = red.quote(alice, sharesToRedeem);
        assertEq(feeBps, 200); // 2%
        assertEq(gross, 1_000 * USDC_UNIT);
        assertEq(fee, gross * 200 / 10_000);
        assertEq(net, gross - fee);

        uint256 reserveBefore = reserve.balance();
        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 returned = red.redeem(sharesToRedeem);
        assertEq(returned, net);
        assertEq(usdc.balanceOf(alice) - aliceBefore, net);
        assertEq(reserve.balance() - reserveBefore, fee);
        // shares burned
        assertEq(shareToken.balanceOf(alice), 9_000 * USDC_UNIT);
    }

    function test_FeeTier_Tier2_90To180Days() public {
        vm.prank(alice);
        sub.subscribe(10_000 * USDC_UNIT);
        skip(100 days);
        _postNAV(1, 1e18);
        (, uint16 bps, , ) = red.quote(alice, 1 * USDC_UNIT);
        assertEq(bps, 100);
    }

    function test_FeeTier_Tier3_OverHalfYear() public {
        vm.prank(alice);
        sub.subscribe(10_000 * USDC_UNIT);
        skip(200 days);
        _postNAV(1, 1e18);
        (, uint16 bps, , ) = red.quote(alice, 1 * USDC_UNIT);
        assertEq(bps, 0);
    }
}
