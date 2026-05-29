// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title IEmergencyController — 守护人紧急熔断
/// @notice 守护人可独立于多签 `pause()`；恢复需治理多签 + Timelock。
interface IEmergencyController {
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event GuardianSet(address indexed guardian, bool active);

    function pause() external; // guardian only
    function unpause() external; // governance only

    function isPaused() external view returns (bool);
    function isGuardian(address account) external view returns (bool);
}
