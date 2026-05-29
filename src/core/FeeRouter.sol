// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeRouter} from "../interfaces/IFeeRouter.sol";
import {IReserveFund} from "../interfaces/IReserveFund.sol";
import {DailyMath} from "../libraries/DailyMath.sol";

/// @title FeeRouter — 费率路由
/// @notice 管理费按日计提（年化 BPS / 365 * AUM）；业绩费按 NAV 高水位法；赎回费 100% 入储备金。
contract FeeRouter is IFeeRouter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable baseAsset;
    address public immutable reserve;
    address public manager;
    address public treasury;

    uint16 public override managementFeeBpsYear; // 如 150 = 1.5%/yr
    uint16 public override performanceFeeBps;    // 如 2000 = 20%
    uint256 public override highWaterMark;       // NAV 高水位（1e18 精度）

    mapping(address => bool) private _spenders;

    error NotAuthorized();

    constructor(address owner_, address baseAsset_, address reserve_, address manager_, address treasury_)
        Ownable(owner_)
    {
        require(baseAsset_ != address(0) && reserve_ != address(0), "FR: zero");
        baseAsset = baseAsset_;
        reserve = reserve_;
        manager = manager_;
        treasury = treasury_;
    }

    modifier onlySpender() {
        if (!_spenders[msg.sender]) revert NotAuthorized();
        _;
    }

    function setSpender(address spender, bool authorized) external onlyOwner {
        _spenders[spender] = authorized;
    }

    function setRates(uint16 mgmtBpsYear, uint16 perfBps) external onlyOwner {
        require(mgmtBpsYear <= 1000 && perfBps <= 5000, "FR: rate"); // 上限：管理 10%/yr, 业绩 50%
        managementFeeBpsYear = mgmtBpsYear;
        performanceFeeBps = perfBps;
    }

    function setManager(address m) external onlyOwner {
        manager = m;
    }

    function setTreasury(address t) external onlyOwner {
        treasury = t;
    }

    function setHighWaterMark(uint256 nav) external onlyOwner {
        highWaterMark = nav;
    }

    /// @notice 由 DailyTick 调用：从 FundVault 拉入按日管理费。
    /// @dev    FundVault 必须先给本合约 approve（或经 spender 模式 transfer）。
    function accrueManagement(uint64 epoch, uint256 aum) external onlySpender nonReentrant {
        uint256 amount = DailyMath.dailyFromAnnualBps(aum, managementFeeBpsYear);
        if (amount > 0) {
            IERC20(baseAsset).safeTransferFrom(msg.sender, address(this), amount);
            emit ManagementAccrued(epoch, amount);
        }
    }

    function accruePerformance(uint64 epoch, uint256 profitAboveHwm) external onlySpender nonReentrant {
        uint256 amount = DailyMath.mulBps(profitAboveHwm, performanceFeeBps);
        if (amount > 0) {
            IERC20(baseAsset).safeTransferFrom(msg.sender, address(this), amount);
            emit PerformanceAccrued(epoch, amount);
        }
    }

    /// @notice 赎回费由 RedemptionManager 推入；100% 直转储备金。
    function receiveRedeemFee(uint256 amount) external onlySpender nonReentrant {
        IERC20(baseAsset).safeTransferFrom(msg.sender, reserve, amount);
        emit RedeemFeeReceived(amount);
    }

    /// @notice 分发已收费用：mgmt 与 perf 通常按预设比例发给 manager / treasury。
    /// @dev    简化版：split 50/50；现实可参数化。
    function distribute() external onlyOwner nonReentrant {
        uint256 bal = IERC20(baseAsset).balanceOf(address(this));
        if (bal == 0) return;
        uint256 half = bal / 2;
        if (manager != address(0) && half > 0) {
            IERC20(baseAsset).safeTransfer(manager, half);
            emit Distributed(manager, half, bytes32("MANAGER"));
        }
        uint256 rest = bal - half;
        if (treasury != address(0) && rest > 0) {
            IERC20(baseAsset).safeTransfer(treasury, rest);
            emit Distributed(treasury, rest, bytes32("TREASURY"));
        }
    }
}
