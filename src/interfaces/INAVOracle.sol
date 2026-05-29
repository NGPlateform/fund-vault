// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title INAVOracle — 每日 NAV 多方签名预言机
/// @notice K-of-N 多签发布日 NAV；偏离上一个 epoch ±maxDeviationBps 自动 reject。
interface INAVOracle {
    event SignerSet(address indexed signer, bool active);
    event ThresholdSet(uint8 threshold);
    event NAVPublished(uint64 indexed epoch, uint256 nav, uint256 totalAssets, uint256 totalSupply);

    struct NAVRecord {
        uint256 nav;          // 1e18 精度的份额单价（baseAsset 计价）
        uint256 totalAssets;  // 当时总资产
        uint256 totalSupply;  // 当时份额总量
        uint64  epoch;
        uint64  publishedAt;  // block.timestamp
    }

    function publish(uint64 epoch, uint256 nav, uint256 totalAssets, uint256 totalSupply, bytes[] calldata sigs) external;

    function latestEpoch() external view returns (uint64);
    function epochPosted(uint64 epoch) external view returns (bool);
    function navAt(uint64 epoch) external view returns (NAVRecord memory);
    function latest() external view returns (NAVRecord memory);
    function isSigner(address account) external view returns (bool);
    function threshold() external view returns (uint8);
    function maxDeviationBps() external view returns (uint16);
}
