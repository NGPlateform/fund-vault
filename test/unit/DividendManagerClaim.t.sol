// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseTest.sol";
import {MerkleRoots} from "src/libraries/MerkleRoots.sol";

/// @notice 测试 DividendManager 的 Merkle 领取（覆盖 MerkleRoots 库）。
contract DividendManagerClaimTest is BaseTest {
    function test_ClaimWithProof_SingleLeafTree() public {
        // 一个 leaf 的 Merkle 树：root = leaf 本身
        uint64 epoch = 1;
        uint256 index = 0;
        uint256 amount = 100 * USDC_UNIT;
        bytes32 leaf = MerkleRoots.leaf(epoch, index, alice, amount);
        bytes32 root = leaf;

        // 预存款：把 amount 推入 DividendManager（pre-funded 模式）
        usdc.mint(gov, amount);
        vm.prank(gov);
        usdc.transfer(address(dividendManager), amount);

        // gov 作为 publisher 直接发布（也加 gov 为 publisher）
        vm.prank(gov);
        dividendManager.setPublisher(gov, true);
        vm.prank(gov);
        dividendManager.publishRoot(epoch, root, amount);

        // claim
        bytes32[] memory proof = new bytes32[](0);
        uint256 before_ = usdc.balanceOf(alice);
        dividendManager.claim(epoch, index, alice, amount, proof);
        assertEq(usdc.balanceOf(alice) - before_, amount);
        assertTrue(dividendManager.isClaimed(epoch, index));
    }

    function test_DoubleClaimReverts() public {
        uint64 epoch = 1;
        uint256 index = 0;
        uint256 amount = 50 * USDC_UNIT;
        bytes32 leaf = MerkleRoots.leaf(epoch, index, alice, amount);

        usdc.mint(gov, amount);
        vm.prank(gov);
        usdc.transfer(address(dividendManager), amount);
        vm.prank(gov);
        dividendManager.setPublisher(gov, true);
        vm.prank(gov);
        dividendManager.publishRoot(epoch, leaf, amount);

        bytes32[] memory proof = new bytes32[](0);
        dividendManager.claim(epoch, index, alice, amount, proof);
        vm.expectRevert();
        dividendManager.claim(epoch, index, alice, amount, proof);
    }

    function test_InvalidProofReverts() public {
        uint64 epoch = 1;
        uint256 index = 0;
        uint256 amount = 50 * USDC_UNIT;
        // 故意用错的 root
        bytes32 wrongRoot = keccak256("wrong");

        usdc.mint(gov, amount);
        vm.prank(gov);
        usdc.transfer(address(dividendManager), amount);
        vm.prank(gov);
        dividendManager.setPublisher(gov, true);
        vm.prank(gov);
        dividendManager.publishRoot(epoch, wrongRoot, amount);

        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert();
        dividendManager.claim(epoch, index, alice, amount, proof);
    }
}
