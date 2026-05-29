// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IKYCRegistry} from "../interfaces/IKYCRegistry.sol";

/// @title KYCRegistry — 申购/持有者白名单
/// @notice 由治理（owner，应为多签 + Timelock）维护。地域代码 jurisdiction code 仅作记录用。
contract KYCRegistry is IKYCRegistry, Ownable {
    mapping(address => bool) private _approved;
    mapping(address => bytes32) private _jurisdiction;

    constructor(address owner_) Ownable(owner_) {}

    function approve(address account, bytes32 jurisdictionCode) external onlyOwner {
        require(account != address(0), "KYC: zero");
        _approved[account] = true;
        _jurisdiction[account] = jurisdictionCode;
        emit Approved(account, jurisdictionCode);
    }

    function revoke(address account) external onlyOwner {
        _approved[account] = false;
        emit Revoked(account);
    }

    function batchApprove(address[] calldata accounts, bytes32[] calldata codes) external onlyOwner {
        require(accounts.length == codes.length, "KYC: length");
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "KYC: zero");
            _approved[accounts[i]] = true;
            _jurisdiction[accounts[i]] = codes[i];
            emit Approved(accounts[i], codes[i]);
        }
    }

    function isApproved(address account) external view returns (bool) {
        return _approved[account];
    }

    function jurisdictionOf(address account) external view returns (bytes32) {
        return _jurisdiction[account];
    }
}
