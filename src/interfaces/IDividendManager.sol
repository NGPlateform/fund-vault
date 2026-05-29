// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IDividendManager — Merkle 根发布与领取
/// @notice 每个 epoch 发布一个 Merkle 根；用户用 `claim(epoch, index, amount, proof)` 领取。
interface IDividendManager {
    event RootPublished(uint64 indexed epoch, bytes32 root, uint256 totalAmount);
    event Claimed(uint64 indexed epoch, address indexed account, uint256 amount);

    function publishRoot(uint64 epoch, bytes32 root, uint256 totalAmount) external;

    function claim(uint64 epoch, uint256 index, address account, uint256 amount, bytes32[] calldata proof)
        external;

    function isClaimed(uint64 epoch, uint256 index) external view returns (bool);
    function rootOf(uint64 epoch) external view returns (bytes32);
    function totalAt(uint64 epoch) external view returns (uint256);
}
