// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {KYCRegistry} from "src/core/KYCRegistry.sol";

contract KYCRegistryTest is Test {
    KYCRegistry public k;
    address gov = address(0x1);
    address alice = address(0xa);

    function setUp() public {
        k = new KYCRegistry(gov);
    }

    function test_ApproveAndRevoke() public {
        vm.prank(gov);
        k.approve(alice, bytes32("SG"));
        assertTrue(k.isApproved(alice));
        assertEq(k.jurisdictionOf(alice), bytes32("SG"));
        vm.prank(gov);
        k.revoke(alice);
        assertFalse(k.isApproved(alice));
    }

    function test_RevertOnNonOwner() public {
        vm.expectRevert();
        k.approve(alice, bytes32("SG"));
    }

    function test_BatchApprove() public {
        address[] memory accts = new address[](2);
        accts[0] = address(0xa);
        accts[1] = address(0xb);
        bytes32[] memory codes = new bytes32[](2);
        codes[0] = bytes32("SG");
        codes[1] = bytes32("HK");
        vm.prank(gov);
        k.batchApprove(accts, codes);
        assertTrue(k.isApproved(accts[0]));
        assertTrue(k.isApproved(accts[1]));
    }
}
