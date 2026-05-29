// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/// @title MockStrategy — 测试用策略适配器
/// @notice 仅供测试。totalAssets = balanceOf(this) + accruedPnl（可由测试 setter 注入）。
///         实战中应替换为对接 CEX/DEX/staking 的真实适配器。
contract MockStrategy is IStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public immutable override baseAsset;
    address public immutable vault;
    int256 public accruedPnl; // signed virtual PnL（测试用 setPnL 注入）

    error NotVault();

    constructor(address owner_, address vault_, address baseAsset_) Ownable(owner_) {
        require(vault_ != address(0) && baseAsset_ != address(0), "MS: zero");
        vault = vault_;
        baseAsset = baseAsset_;
        // 允许 vault 拉回资金（returnFromStrategy）
        IERC20(baseAsset_).approve(vault_, type(uint256).max);
    }

    function deposit(uint256 amount) external {
        // vault 已 transfer 进来，无需额外操作；通知 AllocationManager 调用即可。
        amount;
    }

    function withdraw(uint256 amount) external {
        // vault 会通过 returnFromStrategy 拉回。
        amount;
    }

    /// @notice 测试 setter：模拟策略产生 PnL（正 = 盈利，负 = 亏损）。
    /// @dev    实现：从 owner（部署测试 EOA）拉入/退出 baseAsset 改变本策略账面。
    function setPnL(int256 delta) external onlyOwner {
        if (delta > 0) {
            IERC20(baseAsset).safeTransferFrom(msg.sender, address(this), uint256(delta));
            accruedPnl += delta;
        } else if (delta < 0) {
            uint256 amt = uint256(-delta);
            IERC20(baseAsset).safeTransfer(msg.sender, amt);
            accruedPnl += delta;
        }
    }

    function totalAssets() external view returns (uint256) {
        return IERC20(baseAsset).balanceOf(address(this));
    }
}
