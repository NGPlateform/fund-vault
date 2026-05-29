// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AdapterBase} from "./AdapterBase.sol";

/// @title OptionsMmStrategy — Reference adapter for the Options MM strategy type
/// @notice BTC / ETH options market-making on Deribit / Aevo / Lyra. Profit from
///         bid-ask spread; risk priced into vega / gamma limits + continuous
///         delta hedge via perpetuals. Vega ≤ 0.5% AUM per name; IV > 100
///         triggers MM pause.
///         Target APY 10-18% · max DD -10% (vega events) · capacity 4-6M USDC.
///         Best paired with ThreePoolPolicy (mid-freq PnL fits three-pool) or
///         KellyPolicy. Off-chain reporter: market-making book MTM, with the
///         highest update cadence among the 6 strategies.
/// @dev    Skeleton contract — not deployed. The skeleton reserves an emergency
///         pause path; the reporter may stop accepting new capital when internal
///         risk controls fire.
contract OptionsMmStrategy is AdapterBase {
    constructor(address owner_, address vault_, address baseAsset_, address reporter_)
        AdapterBase(owner_, vault_, baseAsset_, reporter_)
    {}

    function strategyName() external pure override returns (string memory) {
        return "Options MM";
    }

    function strategyKey() external pure override returns (bytes32) {
        return keccak256("OPTIONS_MM_V1");
    }
}
