// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IShareToken — 基金份额代币
/// @notice ERC-20，KYC 白名单受限转移（仅授权 minter/burner 与 KYC 通过的地址间可转移）。
interface IShareToken is IERC20 {
    event MinterSet(address indexed account, bool authorized);
    event BurnerSet(address indexed account, bool authorized);

    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;

    function isMinter(address account) external view returns (bool);
    function isBurner(address account) external view returns (bool);
}
