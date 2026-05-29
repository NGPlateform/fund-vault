// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {FundMultisig} from "src/governance/FundMultisig.sol";

contract Receiver {
    uint256 public x;
    function set(uint256 v) external { x = v; }
}

contract FundMultisigTest is Test {
    FundMultisig public m;
    address a = address(0xA);
    address b = address(0xB);
    address c = address(0xC);
    Receiver public r;

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = a; owners[1] = b; owners[2] = c;
        m = new FundMultisig(owners, 2);
        r = new Receiver();
    }

    function test_SubmitAndExecute_WithThresholdConfirmations() public {
        bytes memory data = abi.encodeWithSelector(Receiver.set.selector, uint256(42));
        vm.prank(a);
        uint256 txId = m.submit(address(r), 0, data);
        // a 已 submit + 自动 confirm = 1 票
        FundMultisig.Transaction memory t = m.getTx(txId);
        assertEq(t.confirmations, 1);

        vm.prank(b);
        m.confirm(txId);
        // 现在 2 票 == threshold
        vm.prank(c);
        m.execute(txId);
        assertEq(r.x(), 42);
        t = m.getTx(txId);
        assertTrue(t.executed);
    }

    function test_InsufficientConfirmations() public {
        bytes memory data = abi.encodeWithSelector(Receiver.set.selector, uint256(7));
        vm.prank(a);
        uint256 txId = m.submit(address(r), 0, data);
        vm.prank(b);
        vm.expectRevert();
        m.execute(txId); // 还没 confirm，b 只有 1 票
    }

    function test_NonOwnerCannotSubmit() public {
        address mallory = address(0xDEAD);
        vm.prank(mallory);
        vm.expectRevert();
        m.submit(address(r), 0, "");
    }

    function test_RevokeConfirmation() public {
        bytes memory data = abi.encodeWithSelector(Receiver.set.selector, uint256(1));
        vm.prank(a);
        uint256 txId = m.submit(address(r), 0, data);
        vm.prank(a);
        m.revoke(txId);
        FundMultisig.Transaction memory t = m.getTx(txId);
        assertEq(t.confirmations, 0);
    }

    function test_AlreadyExecutedReverts() public {
        bytes memory data = abi.encodeWithSelector(Receiver.set.selector, uint256(99));
        vm.prank(a);
        uint256 txId = m.submit(address(r), 0, data);
        vm.prank(b);
        m.confirm(txId);
        vm.prank(c);
        m.execute(txId);
        vm.prank(c);
        vm.expectRevert();
        m.execute(txId);
    }
}
