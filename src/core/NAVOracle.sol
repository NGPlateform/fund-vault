// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {INAVOracle} from "../interfaces/INAVOracle.sol";

/// @title NAVOracle — 每日 NAV 多方签名预言机
/// @notice 至少 threshold 个签名人对 (epoch, nav, totalAssets, totalSupply) 签名后方可上链。
///         偏离上一个 epoch ±maxDeviationBps 自动 reject。
contract NAVOracle is INAVOracle, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    mapping(address => bool) private _signers;
    uint8 public override threshold;
    uint16 public override maxDeviationBps;

    mapping(uint64 => NAVRecord) private _records;
    uint64 public override latestEpoch;

    error NotEnoughSigs();
    error DuplicateSigner();
    error InvalidSigner(address);
    error EpochAlreadyPosted();
    error EpochOutOfOrder();
    error DeviationTooHigh();

    constructor(address owner_, uint8 threshold_, uint16 maxDeviationBps_) Ownable(owner_) {
        require(threshold_ > 0, "NAV: threshold");
        require(maxDeviationBps_ <= 5_000, "NAV: deviation"); // 最高 50%
        threshold = threshold_;
        maxDeviationBps = maxDeviationBps_;
    }

    function setSigner(address account, bool active) external onlyOwner {
        require(account != address(0), "NAV: zero");
        _signers[account] = active;
        emit SignerSet(account, active);
    }

    function setThreshold(uint8 newThreshold) external onlyOwner {
        require(newThreshold > 0, "NAV: threshold");
        threshold = newThreshold;
        emit ThresholdSet(newThreshold);
    }

    /// @notice 发布 epoch 的 NAV。任何人可调，但需提供 ≥ threshold 个有效签名（去重）。
    /// @dev    每个签名是对 keccak256(abi.encode(address(this), epoch, nav, totalAssets, totalSupply))
    ///         的 EIP-191 personal-sign。
    function publish(
        uint64 epoch,
        uint256 nav,
        uint256 totalAssets_,
        uint256 totalSupply_,
        bytes[] calldata sigs
    ) external {
        if (_records[epoch].publishedAt != 0) revert EpochAlreadyPosted();
        if (latestEpoch != 0 && epoch <= latestEpoch) revert EpochOutOfOrder();

        // Deviation check
        if (latestEpoch != 0) {
            uint256 prev = _records[latestEpoch].nav;
            uint256 diff = nav > prev ? nav - prev : prev - nav;
            if (diff * 10_000 > prev * maxDeviationBps) revert DeviationTooHigh();
        }

        bytes32 digest = keccak256(abi.encode(address(this), epoch, nav, totalAssets_, totalSupply_));
        bytes32 ethDigest = digest.toEthSignedMessageHash();

        // 去重统计有效签名
        address[] memory seen = new address[](sigs.length);
        uint256 valid;
        for (uint256 i = 0; i < sigs.length; ++i) {
            address signer = ethDigest.recover(sigs[i]);
            if (!_signers[signer]) revert InvalidSigner(signer);
            // 重复检查
            for (uint256 j = 0; j < valid; ++j) {
                if (seen[j] == signer) revert DuplicateSigner();
            }
            seen[valid] = signer;
            unchecked {
                ++valid;
            }
        }
        if (valid < threshold) revert NotEnoughSigs();

        _records[epoch] = NAVRecord({
            nav: nav,
            totalAssets: totalAssets_,
            totalSupply: totalSupply_,
            epoch: epoch,
            publishedAt: uint64(block.timestamp)
        });
        latestEpoch = epoch;
        emit NAVPublished(epoch, nav, totalAssets_, totalSupply_);
    }

    function epochPosted(uint64 epoch) external view returns (bool) {
        return _records[epoch].publishedAt != 0;
    }

    function navAt(uint64 epoch) external view returns (NAVRecord memory) {
        return _records[epoch];
    }

    function latest() external view returns (NAVRecord memory) {
        return _records[latestEpoch];
    }

    function isSigner(address account) external view returns (bool) {
        return _signers[account];
    }
}
