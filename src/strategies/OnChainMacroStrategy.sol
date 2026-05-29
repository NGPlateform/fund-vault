// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AdapterBase} from "./AdapterBase.sol";

/// @title OnChainMacroStrategy — Reference adapter for the On-Chain Macro strategy type
/// @notice Mid-frequency long/short on BTC/ETH/SOL driven by on-chain indicators
///         (stablecoin net inflow, perp OI, exchange reserves, L2 capital flow, ETF flow).
///         Black-Litterman framework with on-chain factors as posterior; fractional Kelly f*/4.
///         Target APY 20%+ · max DD -25% · capacity 3-5M USDC · 3-14 day holding.
///         Best paired with KellyPolicy (covariance constraint) or Vendor Policy
///         with regime-switching capability. Caution with ThreePoolPolicy
///         (drawdown can break fixed-dividend continuity).
///         Off-chain reporter: requires higher cadence (~every 4 hours) than daily tick.
/// @dev    Skeleton contract — not deployed.
contract OnChainMacroStrategy is AdapterBase {
    constructor(address owner_, address vault_, address baseAsset_, address reporter_)
        AdapterBase(owner_, vault_, baseAsset_, reporter_)
    {}

    function strategyName() external pure override returns (string memory) {
        return "On-Chain Macro";
    }

    function strategyKey() external pure override returns (bytes32) {
        return keccak256("ONCHAIN_MACRO_V1");
    }
}
