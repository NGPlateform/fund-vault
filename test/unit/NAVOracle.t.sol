// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {NAVOracle} from "src/core/NAVOracle.sol";

contract NAVOracleTest is Test {
    NAVOracle public o;
    address gov = address(0x1);

    uint256 constant PK1 = 0xA1;
    uint256 constant PK2 = 0xA2;
    address s1; address s2;

    function setUp() public {
        s1 = vm.addr(PK1);
        s2 = vm.addr(PK2);
        o = new NAVOracle(gov, 2, 2_000);
        vm.startPrank(gov);
        o.setSigner(s1, true);
        o.setSigner(s2, true);
        vm.stopPrank();
    }

    function _sigs(uint64 epoch, uint256 nav, uint256 ta, uint256 ts) internal view returns (bytes[] memory) {
        bytes32 digest = keccak256(abi.encode(address(o), epoch, nav, ta, ts));
        bytes32 eth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        bytes[] memory out = new bytes[](2);
        (uint8 v1, bytes32 r1, bytes32 ss1) = vm.sign(PK1, eth);
        out[0] = abi.encodePacked(r1, ss1, v1);
        (uint8 v2, bytes32 r2, bytes32 ss2) = vm.sign(PK2, eth);
        out[1] = abi.encodePacked(r2, ss2, v2);
        return out;
    }

    function test_PublishWithEnoughSigs() public {
        bytes[] memory sigs = _sigs(1, 1e18, 1000, 1000);
        o.publish(1, 1e18, 1000, 1000, sigs);
        assertEq(o.latestEpoch(), 1);
        assertEq(o.latest().nav, 1e18);
    }

    function test_RevertIfDeviationTooHigh() public {
        bytes[] memory sigs1 = _sigs(1, 1e18, 1000, 1000);
        o.publish(1, 1e18, 1000, 1000, sigs1);
        // 偏离 30%（超过 20% 上限）
        bytes[] memory sigs2 = _sigs(2, 13e17, 1300, 1000);
        vm.expectRevert();
        o.publish(2, 13e17, 1300, 1000, sigs2);
    }

    function test_RevertIfEpochOutOfOrder() public {
        bytes[] memory sigs1 = _sigs(2, 1e18, 1000, 1000);
        o.publish(2, 1e18, 1000, 1000, sigs1);
        bytes[] memory sigs2 = _sigs(1, 1e18, 1000, 1000);
        vm.expectRevert();
        o.publish(1, 1e18, 1000, 1000, sigs2);
    }

    function test_RevertIfDuplicateSigner() public {
        bytes32 digest = keccak256(abi.encode(address(o), uint64(1), uint256(1e18), uint256(1000), uint256(1000)));
        bytes32 eth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK1, eth);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = abi.encodePacked(r, s, v);
        sigs[1] = abi.encodePacked(r, s, v); // same signer twice
        vm.expectRevert();
        o.publish(1, 1e18, 1000, 1000, sigs);
    }
}
