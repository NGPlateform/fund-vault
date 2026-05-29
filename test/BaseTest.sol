// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {KYCRegistry} from "src/core/KYCRegistry.sol";
import {EmergencyController} from "src/core/EmergencyController.sol";
import {ShareToken} from "src/core/ShareToken.sol";
import {NAVOracle} from "src/core/NAVOracle.sol";
import {FundVault} from "src/core/FundVault.sol";
import {AllocationManager} from "src/core/AllocationManager.sol";
import {ReserveFund} from "src/core/ReserveFund.sol";
import {DividendManager} from "src/core/DividendManager.sol";
import {SubscriptionManager} from "src/core/SubscriptionManager.sol";
import {RedemptionManager} from "src/core/RedemptionManager.sol";
import {DailyTick} from "src/core/DailyTick.sol";
import {ThreePoolPolicy} from "src/policies/ThreePoolPolicy.sol";
import {KellyPolicy} from "src/policies/KellyPolicy.sol";
import {MockStrategy} from "src/strategies/MockStrategy.sol";
import {INAVOracle} from "src/interfaces/INAVOracle.sol";
import {ISettlementPolicy} from "src/interfaces/ISettlementPolicy.sol";

/// @notice Mock USDC-like token: 6 decimals
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

abstract contract BaseTest is Test {
    // Actors
    address public gov = makeAddr("governance");
    address public guardian = makeAddr("guardian");
    address public manager = makeAddr("manager");
    address public treasury = makeAddr("treasury");
    address public keeper = makeAddr("keeper");

    // 3 NAV signers (threshold 2)
    uint256 internal constant SIGNER1_PK = 0xA1;
    uint256 internal constant SIGNER2_PK = 0xA2;
    uint256 internal constant SIGNER3_PK = 0xA3;
    address public signer1;
    address public signer2;
    address public signer3;

    // Users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Contracts
    MockUSDC public usdc;
    KYCRegistry public kyc;
    EmergencyController public emergency;
    ShareToken public shareToken;
    NAVOracle public navOracle;
    FundVault public vault;
    AllocationManager public allocation;
    ReserveFund public reserve;
    DividendManager public dividendManager;
    SubscriptionManager public sub;
    RedemptionManager public red;
    DailyTick public dailyTick;
    ThreePoolPolicy public threePool;
    KellyPolicy public kelly;
    MockStrategy public strat;

    uint256 internal constant DAY = 1 days;
    uint256 internal constant USDC_UNIT = 1e6;

    function setUp() public virtual {
        // 让 block.timestamp 处在一个合理位置，避免 23h minInterval 启动期阻塞测试
        vm.warp(365 days);

        signer1 = vm.addr(SIGNER1_PK);
        signer2 = vm.addr(SIGNER2_PK);
        signer3 = vm.addr(SIGNER3_PK);

        usdc = new MockUSDC();

        kyc = new KYCRegistry(gov);
        emergency = new EmergencyController(gov);
        shareToken = new ShareToken("F-Star Fund Share", "FUSF", 6, gov, address(kyc));
        navOracle = new NAVOracle(gov, 2, 2_000); // threshold 2, max 20% dev
        vault = new FundVault(gov, address(usdc));
        allocation = new AllocationManager(gov, address(vault));
        reserve = new ReserveFund(gov, address(usdc));
        dividendManager = new DividendManager(gov, address(usdc));

        threePool = new ThreePoolPolicy(
            gov,
            ThreePoolPolicy.Params({
                fixedYieldBpsYear: 600,    // 6%/yr
                floatBps: 3000,            // 30%
                toNAVBps: 6000,            // 60%
                reserveInjectBps: 1000,    // 10%
                reserveCapBps: 2500,       // 25% AUM
                reserveFloorBps: 500       // 5% AUM
            })
        );
        kelly = new KellyPolicy(
            gov,
            KellyPolicy.Params({
                kellyFractionBps: 2500,    // 1/4 Kelly = 25% of profit as dividend
                reserveInjectBps: 1500,    // 15%
                toNAVBps: 6000,            // 60%
                reserveCapBps: 2500,
                reserveFloorBps: 500
            })
        );

        sub = new SubscriptionManager(
            gov, address(kyc), address(shareToken), address(navOracle), address(emergency),
            address(usdc), address(vault), 1_000 * USDC_UNIT, 30 days
        );
        red = new RedemptionManager(
            gov, address(shareToken), address(navOracle), address(vault), address(emergency),
            address(sub), address(reserve)
        );
        dailyTick = new DailyTick(
            gov, address(vault), address(allocation), address(navOracle),
            address(reserve), address(dividendManager), address(emergency), address(threePool)
        );

        strat = new MockStrategy(gov, address(vault), address(usdc));

        // Wire authorizations (gov is the deployer/owner)
        vm.startPrank(gov);
        shareToken.setMinter(address(sub), true);
        shareToken.setBurner(address(red), true);
        sub.setRedemptionManager(address(red));

        vault.setSpender(address(sub), true);
        vault.setSpender(address(red), true);
        vault.setSpender(address(allocation), true);
        vault.setSpender(address(dailyTick), true);

        reserve.setSpender(address(dailyTick), true);
        dividendManager.setPublisher(address(dailyTick), true);

        emergency.setGuardian(guardian, true);

        // Redemption fee tiers: < 90d=2%, 90-180=1%, ≥180=0
        RedemptionManager.FeeTier[] memory tiers = new RedemptionManager.FeeTier[](3);
        tiers[0] = RedemptionManager.FeeTier({maxDays: 89, bps: 200});
        tiers[1] = RedemptionManager.FeeTier({maxDays: 179, bps: 100});
        tiers[2] = RedemptionManager.FeeTier({maxDays: type(uint32).max, bps: 0});
        red.setFeeTiers(tiers);

        // NAV signers
        navOracle.setSigner(signer1, true);
        navOracle.setSigner(signer2, true);
        navOracle.setSigner(signer3, true);

        // KYC alice + bob
        kyc.approve(alice, bytes32("SG"));
        kyc.approve(bob, bytes32("SG"));

        // Add MockStrategy at 80% weight（cap 80%）—— 留 20% 在 vault 作为 idle 应对每日动作
        allocation.addStrategy(address(strat), 8_000, 8_000);
        vm.stopPrank();

        // Mint USDC to alice/bob & approve sub
        usdc.mint(alice, 1_000_000 * USDC_UNIT);
        usdc.mint(bob, 1_000_000 * USDC_UNIT);
        vm.prank(alice);
        usdc.approve(address(sub), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(sub), type(uint256).max);
    }

    // ---- helpers ----

    /// @dev 多签生成 NAV 签名 (signer1 + signer2)
    function _navSigs(uint64 epoch, uint256 nav, uint256 totalAssets, uint256 totalSupply)
        internal
        view
        returns (bytes[] memory sigs)
    {
        bytes32 digest = keccak256(abi.encode(address(navOracle), epoch, nav, totalAssets, totalSupply));
        bytes32 eth = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        sigs = new bytes[](2);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(SIGNER1_PK, eth);
        sigs[0] = abi.encodePacked(r1, s1, v1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(SIGNER2_PK, eth);
        sigs[1] = abi.encodePacked(r2, s2, v2);
    }

    function _postNAV(uint64 epoch, uint256 nav) internal {
        uint256 totalAssets = allocation.totalAssets();
        uint256 supply = shareToken.totalSupply();
        bytes[] memory sigs = _navSigs(epoch, nav, totalAssets, supply);
        navOracle.publish(epoch, nav, totalAssets, supply, sigs);
    }
}
