// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AdapterBase} from "./AdapterBase.sol";

/// @title VentureLiquidStrategy — Reference adapter for the Venture-Liquid strategy type
/// @notice Vetted early-stage token positions. Translates traditional VC
///         odds-seeking into 24/7-liquid on-chain markets, gated by 4-stage
///         due diligence (team / tokenomics / audit / liquidity). Pass rate <15%.
///         Per-position ≤ 5% sleeve, top-5 concentration ≤ 50%.
///         Target IRR 30%+ · max single position 5% sleeve · lockup 12-24 months.
///         Requires Vendor Policy (incompatible with ThreePoolPolicy fixed-dividend).
///         Off-chain reporter: investment committee + custodian.
/// @dev    Skeleton contract — not deployed. Reserves a token whitelist + lockup
///         timestamp surface (both governance-approved). The due-diligence
///         framework is the fund's own alpha and is not on-chain.
contract VentureLiquidStrategy is AdapterBase {
    /// @notice 锁定期截止（lockup deadline · 由治理设置）
    uint64 public lockupUntil;

    /// @notice 白名单代币（早期项目代币 · 由治理添加）
    mapping(address => bool) public isWhitelisted;

    event LockupSet(uint64 lockupUntil);
    event TokenWhitelisted(address indexed token, bool approved);

    constructor(address owner_, address vault_, address baseAsset_, address reporter_)
        AdapterBase(owner_, vault_, baseAsset_, reporter_)
    {}

    /// @notice 治理设置锁定期截止时间
    function setLockup(uint64 newLockupUntil) external onlyOwner {
        lockupUntil = newLockupUntil;
        emit LockupSet(newLockupUntil);
    }

    /// @notice 治理批准白名单代币
    function setWhitelist(address token, bool approved) external onlyOwner {
        isWhitelisted[token] = approved;
        emit TokenWhitelisted(token, approved);
    }

    function strategyName() external pure override returns (string memory) {
        return "Venture-Liquid";
    }

    function strategyKey() external pure override returns (bytes32) {
        return keccak256("VENTURE_LIQUID_V1");
    }
}
