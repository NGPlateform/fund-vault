// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFundVault} from "../interfaces/IFundVault.sol";

/// @title FundVault — 基金资产唯一链上托管
/// @notice 仅 baseAsset 一种 ERC-20。授权 spender（核心合约：SubscriptionManager / RedemptionManager
///         / DailyTick / AllocationManager）通过 requestPayout / deployToStrategy / returnFromStrategy
///         触发资金动作。普通用户不可直接调用。
contract FundVault is IFundVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable override baseAsset;

    mapping(address => bool) private _spenders;
    mapping(address => uint256) private _deployed;
    uint256 private _totalDeployed;

    error NotAuthorized();

    constructor(address owner_, address baseAsset_) Ownable(owner_) {
        require(baseAsset_ != address(0), "Vault: asset zero");
        baseAsset = baseAsset_;
    }

    modifier onlySpender() {
        if (!_spenders[msg.sender]) revert NotAuthorized();
        _;
    }

    function setSpender(address spender, bool authorized) external onlyOwner {
        require(spender != address(0), "Vault: zero");
        _spenders[spender] = authorized;
        emit SpenderAuthorized(spender, authorized);
    }

    function requestPayout(address to, uint256 amount) external override onlySpender nonReentrant {
        require(to != address(0), "Vault: to zero");
        IERC20(baseAsset).safeTransfer(to, amount);
        emit PayoutRequested(msg.sender, to, amount);
    }

    function deployToStrategy(address strategy, uint256 amount) external override onlySpender nonReentrant {
        require(strategy != address(0), "Vault: strategy zero");
        _deployed[strategy] += amount;
        _totalDeployed += amount;
        IERC20(baseAsset).safeTransfer(strategy, amount);
        emit DeployedToStrategy(strategy, amount);
    }

    function returnFromStrategy(address strategy, uint256 amount) external override onlySpender nonReentrant {
        require(strategy != address(0), "Vault: strategy zero");
        uint256 d = _deployed[strategy];
        // 归还可大于划拨（盈利）或小于划拨（亏损 / 部分归还）
        if (amount > d) {
            _deployed[strategy] = 0;
            _totalDeployed -= d;
        } else {
            _deployed[strategy] = d - amount;
            _totalDeployed -= amount;
        }
        IERC20(baseAsset).safeTransferFrom(strategy, address(this), amount);
        emit ReturnedFromStrategy(strategy, amount);
    }

    function isSpender(address account) external view returns (bool) {
        return _spenders[account];
    }

    function deployedTo(address strategy) external view returns (uint256) {
        return _deployed[strategy];
    }

    function balanceBreakdown() external view returns (uint256 idle, uint256 deployed) {
        idle = IERC20(baseAsset).balanceOf(address(this));
        deployed = _totalDeployed;
    }
}
