// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AdapterBase} from "./AdapterBase.sol";

/// @title ActiveAlphaStrategy — Reference adapter for the Active Alpha strategy type
/// @notice Multi-strategy quant book (funding rate / cross-market arb / options MM / event-driven)
///         weighted by fractional Kelly + covariance matrix constraint.
///         Target geo mean 15-25% · max DD -15% · capacity 5-8M USDC per sleeve.
///         Best paired with ThreePoolPolicy (float dividend) or KellyPolicy.
///         Off-chain reporter: institutional quant trading desk.
/// @dev    Skeleton contract — not deployed. Real trading logic lives off-chain;
///         this contract only exposes the IStrategy adapter surface.
contract ActiveAlphaStrategy is AdapterBase {
    constructor(address owner_, address vault_, address baseAsset_, address reporter_)
        AdapterBase(owner_, vault_, baseAsset_, reporter_)
    {}

    function strategyName() external pure override returns (string memory) {
        return "Active Alpha";
    }

    function strategyKey() external pure override returns (bytes32) {
        return keccak256("ACTIVE_ALPHA_V1");
    }
}
