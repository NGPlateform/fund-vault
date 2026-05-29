// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AdapterBase} from "./AdapterBase.sol";

/// @title YieldPlusStrategy — Reference adapter for the Yield+ strategy type
/// @notice Stablecoin + RWA treasury smart aggregation: Aave V3 / Morpho / sUSDS (T+0 floor),
///         BlackRock BUIDL / Ondo USDY (T+1 core), Pendle PT (tactical).
///         Target APY 6-9% · max DD <2% · capacity 50M+ USDC · zero leverage.
///         Best paired with KellyPolicy (idle floor for no-fixed-dividend funds) or
///         ThreePoolPolicy (A-pool interest source covering daily 6%/365 payout).
///         Off-chain reporter: keeper polling DeFi protocols + RWA NAV oracles.
/// @dev    Skeleton contract — not deployed. Closest of the 6 to a real implementation,
///         since counterparties are public DeFi contracts callable from this adapter.
contract YieldPlusStrategy is AdapterBase {
    constructor(address owner_, address vault_, address baseAsset_, address reporter_)
        AdapterBase(owner_, vault_, baseAsset_, reporter_)
    {}

    function strategyName() external pure override returns (string memory) {
        return "Yield+";
    }

    function strategyKey() external pure override returns (bytes32) {
        return keccak256("YIELD_PLUS_V1");
    }
}
