// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/// @title AdapterBase — 参考策略 adapter 通用基类（骨架）
/// @notice 为 6 个参考策略类型提供最小 IStrategy 实现。资金流：
///         1. FundVault.requestPayout(strategy, amount) → 推送 baseAsset 给本合约
///         2. AllocationManager 调用 strategy.deposit(amount) 通知入账
///         3. 链下策略系统（reporter）调用 reportTotalAssets() 更新账面价值
///         4. 撤资时 strategy.withdraw(amount)，由 vault 通过 returnFromStrategy 拉回
///
///         本基类不实做真实的链下对接——每个接入基金按自家 alpha / 协议路由扩展派生类。
///         strategyName / strategyKey / reporter 等差异化点由派生类定义。
abstract contract AdapterBase is IStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public immutable override baseAsset;
    address public immutable vault;
    address public reporter;          // 链下策略系统的报告者地址（可由 governance 改）
    uint256 internal _reportedTotal;  // 由 reporter 注入的账面总价值（含本金+盈亏）

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Reported(uint256 newTotal);
    event ReporterSet(address indexed reporter);

    error NotVault();
    error NotReporter();

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    modifier onlyReporter() {
        if (msg.sender != reporter) revert NotReporter();
        _;
    }

    constructor(address owner_, address vault_, address baseAsset_, address reporter_) Ownable(owner_) {
        require(vault_ != address(0) && baseAsset_ != address(0), "Adapter: zero");
        vault = vault_;
        baseAsset = baseAsset_;
        reporter = reporter_;
        // 允许 vault 通过 returnFromStrategy 拉回
        IERC20(baseAsset_).approve(vault_, type(uint256).max);
    }

    /// @notice 治理可替换 reporter（链下系统迁移）
    function setReporter(address newReporter) external onlyOwner {
        reporter = newReporter;
        emit ReporterSet(newReporter);
    }

    /// @notice 链下策略系统在结算前更新当前账面总价值（含未归还本金 + 浮动 PnL）
    /// @dev    真实接入：reporter 从 CEX/DEX/DeFi 协议查询当前持仓价值并签名调用
    function reportTotalAssets(uint256 newTotal) external onlyReporter {
        _reportedTotal = newTotal;
        emit Reported(newTotal);
    }

    /// @notice IStrategy: Vault 推送 baseAsset 后通知入账（资金已在合约内）
    function deposit(uint256 amount) external onlyVault {
        _reportedTotal += amount;
        emit Deposited(amount);
    }

    /// @notice IStrategy: Vault 申请提取（由 vault 通过 returnFromStrategy 拉回 baseAsset）
    function withdraw(uint256 amount) external onlyVault {
        require(amount <= _reportedTotal, "Adapter: insufficient");
        _reportedTotal -= amount;
        emit Withdrawn(amount);
    }

    /// @notice IStrategy: 当前账面总价值
    function totalAssets() external view returns (uint256) {
        return _reportedTotal;
    }

    /// @notice 派生类用：策略人类可读名（用于事件解析与 ABI 标识）
    function strategyName() external view virtual returns (string memory);

    /// @notice 派生类用：策略唯一标识（如 keccak256("ACTIVE_ALPHA_V1")）
    function strategyKey() external view virtual returns (bytes32);
}
