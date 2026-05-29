// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title DailyMath — 日级别费率/分红辅助
library DailyMath {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant DAYS_PER_YEAR = 365;

    /// @notice 把年化 BPS 转换为日级 amount = principal * yearBps / 10000 / 365。
    function dailyFromAnnualBps(uint256 principal, uint16 yearBps) internal pure returns (uint256) {
        return (principal * yearBps) / BPS / DAYS_PER_YEAR;
    }

    /// @notice mulBps：amount * bps / 10000，向下取整。
    function mulBps(uint256 amount, uint16 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS;
    }

    /// @notice 比例除：当 cap < target 时按 cap 截断。
    function cappedTo(uint256 amount, uint256 cap) internal pure returns (uint256) {
        return amount > cap ? cap : amount;
    }

    /// @notice abs(int256) → uint256，避免 INT256_MIN 极端情况。
    function absInt(int256 x) internal pure returns (uint256) {
        unchecked {
            return x >= 0 ? uint256(x) : uint256(-x);
        }
    }
}
