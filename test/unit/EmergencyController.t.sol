// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {EmergencyController} from "src/core/EmergencyController.sol";

contract EmergencyControllerTest is Test {
    EmergencyController public e;
    address gov = address(0x1);
    address g1 = address(0xA);
    address g2 = address(0xB);

    function setUp() public {
        e = new EmergencyController(gov);
        vm.startPrank(gov);
        e.setGuardian(g1, true);
        vm.stopPrank();
    }

    function test_GuardianCanPause() public {
        assertFalse(e.isPaused());
        vm.prank(g1);
        e.pause();
        assertTrue(e.isPaused());
    }

    function test_NonGuardianCannotPause() public {
        vm.prank(g2);
        vm.expectRevert();
        e.pause();
    }

    function test_OwnerCanUnpause() public {
        vm.prank(g1);
        e.pause();
        assertTrue(e.isPaused());
        vm.prank(gov);
        e.unpause();
        assertFalse(e.isPaused());
    }

    function test_NonOwnerCannotUnpause() public {
        vm.prank(g1);
        e.pause();
        vm.prank(g1);
        vm.expectRevert();
        e.unpause();
    }

    function test_PauseIdempotent() public {
        vm.startPrank(g1);
        e.pause();
        e.pause();
        vm.stopPrank();
        assertTrue(e.isPaused());
    }
}
