// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDividendManager} from "../interfaces/IDividendManager.sol";
import {MerkleRoots} from "../libraries/MerkleRoots.sol";

/// @title DividendManager — Merkle 根发布 + 持有人领取
/// @notice DailyTick 推入 baseAsset 并发布根；持有人按 (epoch, index, account, amount) 领取。
contract DividendManager is IDividendManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable baseAsset;
    mapping(address => bool) private _publishers;

    mapping(uint64 => bytes32) private _roots;
    mapping(uint64 => uint256) private _totals;
    mapping(uint64 => mapping(uint256 => bool)) private _claimedBitmap; // epoch → index → bool

    error NotPublisher();
    error AlreadyPublished();
    error AlreadyClaimed();
    error InvalidProof();
    error InsufficientFunds();

    constructor(address owner_, address baseAsset_) Ownable(owner_) {
        require(baseAsset_ != address(0), "DM: asset zero");
        baseAsset = baseAsset_;
    }

    function setPublisher(address account, bool active) external onlyOwner {
        _publishers[account] = active;
    }

    function publishRoot(uint64 epoch, bytes32 root, uint256 totalAmount) external nonReentrant {
        if (!_publishers[msg.sender]) revert NotPublisher();
        if (_roots[epoch] != bytes32(0)) revert AlreadyPublished();
        // 预存款模式：publisher（DailyTick）先经 FundVault.requestPayout 将 totalAmount 推入本合约，
        // 再调用 publishRoot。本函数仅核实余额。
        if (totalAmount > 0 && IERC20(baseAsset).balanceOf(address(this)) < totalAmount) {
            revert InsufficientFunds();
        }
        _roots[epoch] = root;
        _totals[epoch] = totalAmount;
        emit RootPublished(epoch, root, totalAmount);
    }

    function claim(uint64 epoch, uint256 index, address account, uint256 amount, bytes32[] calldata proof)
        external
        nonReentrant
    {
        if (_claimedBitmap[epoch][index]) revert AlreadyClaimed();
        bytes32 root = _roots[epoch];
        require(root != bytes32(0), "DM: no root");
        bytes32 node = MerkleRoots.leaf(epoch, index, account, amount);
        if (!MerkleRoots.verify(proof, root, node)) revert InvalidProof();
        _claimedBitmap[epoch][index] = true;
        IERC20(baseAsset).safeTransfer(account, amount);
        emit Claimed(epoch, account, amount);
    }

    function isClaimed(uint64 epoch, uint256 index) external view returns (bool) {
        return _claimedBitmap[epoch][index];
    }

    function rootOf(uint64 epoch) external view returns (bytes32) {
        return _roots[epoch];
    }

    function totalAt(uint64 epoch) external view returns (uint256) {
        return _totals[epoch];
    }

    function isPublisher(address account) external view returns (bool) {
        return _publishers[account];
    }
}
