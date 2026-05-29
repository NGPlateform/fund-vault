// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IReserveFund — 储备金账户
/// @notice 由 Policy 通过 DailyTick 触发注入/支取。封顶 reserveCapBps（如 25% AUM）；
///         硬底线 reserveFloorBps（如 5% AUM）— 触发后由 Policy 决定是否暂停浮动分红。
interface IReserveFund {
    event Injected(uint256 amount, uint256 newBalance);
    event Drawn(uint256 amount, uint256 newBalance);

    function inject(uint256 amount) external; // 从 FundVault 推入
    function draw(uint256 amount, address to) external; // 推出到指定地址（通常 FundVault）

    function balance() external view returns (uint256);
    function baseAsset() external view returns (address);
}
