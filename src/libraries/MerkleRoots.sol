// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title MerkleRoots — Merkle proof 校验（OpenZeppelin 同款实现的最小子集）
/// @dev leaf = keccak256(abi.encodePacked(epoch, index, account, amount))
library MerkleRoots {
    function leaf(uint64 epoch, uint256 index, address account, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(bytes.concat(keccak256(abi.encode(epoch, index, account, amount))));
    }

    function verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf_) internal pure returns (bool) {
        bytes32 computed = leaf_;
        for (uint256 i = 0; i < proof.length; ++i) {
            bytes32 sib = proof[i];
            computed = computed <= sib
                ? keccak256(abi.encodePacked(computed, sib))
                : keccak256(abi.encodePacked(sib, computed));
        }
        return computed == root;
    }
}
