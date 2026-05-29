// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IFeeRouter — 费率路由
/// @notice 管理费按日计提（year-bps / 365）；业绩费按高水位法（hwm）；申购/赎回费由对应 Manager
///         直接划付。FeeRouter 持有费用余额并按预设比例分发给 manager、treasury、reserve。
interface IFeeRouter {
    event ManagementAccrued(uint64 indexed epoch, uint256 amount);
    event PerformanceAccrued(uint64 indexed epoch, uint256 amount);
    event RedeemFeeReceived(uint256 amount);
    event Distributed(address indexed to, uint256 amount, bytes32 kind);

    /// @notice 由 DailyTick 调用计提管理费；从 vault 划转入 FeeRouter。
    function accrueManagement(uint64 epoch, uint256 aum) external;

    /// @notice 由 DailyTick 在 NAV 高水位被刷新时调用计提业绩费。
    function accruePerformance(uint64 epoch, uint256 profitAboveHwm) external;

    /// @notice 赎回费推入；100% 入储备（实现细节）。
    function receiveRedeemFee(uint256 amount) external;

    function managementFeeBpsYear() external view returns (uint16);
    function performanceFeeBps() external view returns (uint16);
    function highWaterMark() external view returns (uint256);
}
