// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AdapterBase} from "./AdapterBase.sol";

/// @title StakingMevStrategy — Reference adapter for the Staking & MEV strategy type
/// @notice Institutional ETH staking + LST liquidity arbitrage + cross-domain MEV.
///         Targets ETH + 5% by stacking validator rewards, stETH/wstETH spread arb,
///         weETH / re-staking, and MEV-Boost relay selection / MEV smoothing pool.
///         Target APY ETH+5% · max DD <5% (ex slashing) · capacity 20M+ USDC eq.
///         Best paired with ThreePoolPolicy or KellyPolicy. Off-chain reporter:
///         keeper aggregating validator state + LST balances.
/// @dev    Skeleton contract — not deployed. Note: real Staking & MEV would set
///         baseAsset = WETH (not USDC). Current fund-vault MVP is single-USDC;
///         multi-asset baseAsset support is on the roadmap.
contract StakingMevStrategy is AdapterBase {
    constructor(address owner_, address vault_, address baseAsset_, address reporter_)
        AdapterBase(owner_, vault_, baseAsset_, reporter_)
    {}

    function strategyName() external pure override returns (string memory) {
        return "Staking & MEV";
    }

    function strategyKey() external pure override returns (bytes32) {
        return keccak256("STAKING_MEV_V1");
    }
}
