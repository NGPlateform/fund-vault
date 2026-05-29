// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IKYCRegistry — 地址白名单 + 地域代码
/// @notice 仅 isApproved(addr) == true 的地址可申购、持有、转移份额。
interface IKYCRegistry {
    event Approved(address indexed account, bytes32 jurisdictionCode);
    event Revoked(address indexed account);

    function approve(address account, bytes32 jurisdictionCode) external;
    function revoke(address account) external;

    function isApproved(address account) external view returns (bool);
    function jurisdictionOf(address account) external view returns (bytes32);
}
