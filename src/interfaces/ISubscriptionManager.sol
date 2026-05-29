// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title ISubscriptionManager — 申购管理
/// @notice 接收 baseAsset → 按当前 NAV 铸造 ShareToken → 记录锁定期截止时间。
interface ISubscriptionManager {
    struct Deposit {
        uint256 amount;       // baseAsset 金额
        uint256 sharesMinted; // 铸出的份额
        uint64  depositedAt;
        uint64  unlockAt;
    }

    event Subscribed(
        address indexed account,
        uint256 amount,
        uint256 shares,
        uint256 navUsed,
        uint64  unlockAt
    );
    event MinSubscriptionSet(uint256 amount);
    event LockupSet(uint32 secs);

    function subscribe(uint256 amount) external returns (uint256 shares);

    function depositsOf(address account) external view returns (Deposit[] memory);
    function freeShares(address account) external view returns (uint256);
    function lockedShares(address account) external view returns (uint256);

    function minSubscription() external view returns (uint256);
    function lockupSecs() external view returns (uint32);
}
