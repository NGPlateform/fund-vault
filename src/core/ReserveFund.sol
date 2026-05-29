// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReserveFund} from "../interfaces/IReserveFund.sol";

/// @title ReserveFund — 储备金账户
/// @notice 单一 baseAsset；inject 由 DailyTick 推入；draw 由 DailyTick 拉出兜底分红。
contract ReserveFund is IReserveFund, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable override baseAsset;
    mapping(address => bool) private _spenders;

    error NotAuthorized();

    constructor(address owner_, address baseAsset_) Ownable(owner_) {
        require(baseAsset_ != address(0), "RF: asset zero");
        baseAsset = baseAsset_;
    }

    modifier onlySpender() {
        if (!_spenders[msg.sender]) revert NotAuthorized();
        _;
    }

    function setSpender(address spender, bool authorized) external onlyOwner {
        require(spender != address(0), "RF: zero");
        _spenders[spender] = authorized;
    }

    /// @notice 注入：调用前由 spender 给本合约 approve；本合约 transferFrom 拉入。
    function inject(uint256 amount) external onlySpender nonReentrant {
        IERC20(baseAsset).safeTransferFrom(msg.sender, address(this), amount);
        emit Injected(amount, balance());
    }

    function draw(uint256 amount, address to) external onlySpender nonReentrant {
        require(to != address(0), "RF: to zero");
        IERC20(baseAsset).safeTransfer(to, amount);
        emit Drawn(amount, balance());
    }

    function balance() public view returns (uint256) {
        return IERC20(baseAsset).balanceOf(address(this));
    }

    function isSpender(address account) external view returns (bool) {
        return _spenders[account];
    }
}
