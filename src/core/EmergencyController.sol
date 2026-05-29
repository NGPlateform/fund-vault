// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEmergencyController} from "../interfaces/IEmergencyController.sol";

/// @title EmergencyController — 守护人 pause / 治理 unpause
/// @notice 多名守护人之一即可触发 pause；恢复必须经由 owner（治理多签 + Timelock）。
contract EmergencyController is IEmergencyController, Ownable {
    bool private _paused;
    mapping(address => bool) private _guardians;

    error NotGuardian();

    constructor(address owner_) Ownable(owner_) {}

    function setGuardian(address guardian, bool active) external onlyOwner {
        require(guardian != address(0), "EC: zero");
        _guardians[guardian] = active;
        emit GuardianSet(guardian, active);
    }

    function pause() external {
        if (!_guardians[msg.sender] && msg.sender != owner()) revert NotGuardian();
        if (!_paused) {
            _paused = true;
            emit Paused(msg.sender);
        }
    }

    function unpause() external onlyOwner {
        if (_paused) {
            _paused = false;
            emit Unpaused(msg.sender);
        }
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    function isGuardian(address account) external view returns (bool) {
        return _guardians[account];
    }
}
