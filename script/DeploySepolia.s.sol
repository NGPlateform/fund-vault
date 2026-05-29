// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
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
import {FundMultisig} from "src/governance/FundMultisig.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC (fund-vault dry-run)", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @notice Sepolia dry-run 部署：deployer 即 gov，所有合约 owner = deployer。
///         实战需在事后通过 FundMultisig 接管 ownership。
contract DeploySepolia is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address gov = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 0) MockUSDC（Sepolia 无 USDC；deploy 一份）
        MockUSDC usdc = new MockUSDC();
        usdc.mint(gov, 1_000_000_000 * 1e6); // 10 亿 USDC 给 deployer 测试用

        // 1) 合规与安全
        KYCRegistry kyc = new KYCRegistry(gov);
        EmergencyController emergency = new EmergencyController(gov);

        // 2) 份额代币
        ShareToken shareToken = new ShareToken(
            "F-Star Fund Share",
            "FUSF",
            6,
            gov,
            address(kyc)
        );

        // 3) NAV 预言机（2/3 threshold, ±20% deviation）
        NAVOracle navOracle = new NAVOracle(gov, 2, 2000);

        // 4) 资产托管 + 配置
        FundVault vault = new FundVault(gov, address(usdc));
        AllocationManager allocation = new AllocationManager(gov, address(vault));

        // 5) 储备 + 分红
        ReserveFund reserve = new ReserveFund(gov, address(usdc));
        DividendManager dividendManager = new DividendManager(gov, address(usdc));

        // 6) Policy（部署两个供选）
        ThreePoolPolicy threePool = new ThreePoolPolicy(
            gov,
            ThreePoolPolicy.Params({
                fixedYieldBpsYear: 600,
                floatBps: 3000,
                toNAVBps: 6000,
                reserveInjectBps: 1000,
                reserveCapBps: 2500,
                reserveFloorBps: 500
            })
        );
        KellyPolicy kelly = new KellyPolicy(
            gov,
            KellyPolicy.Params({
                kellyFractionBps: 2500,
                reserveInjectBps: 1500,
                toNAVBps: 6000,
                reserveCapBps: 2500,
                reserveFloorBps: 500
            })
        );

        // 7) 申赎
        SubscriptionManager sub = new SubscriptionManager(
            gov,
            address(kyc),
            address(shareToken),
            address(navOracle),
            address(emergency),
            address(usdc),
            address(vault),
            1_000 * 1e6, // 最低申购 1000 USDC
            30 days
        );
        RedemptionManager red = new RedemptionManager(
            gov,
            address(shareToken),
            address(navOracle),
            address(vault),
            address(emergency),
            address(sub),
            address(reserve)
        );

        // 8) DailyTick（默认采用 ThreePoolPolicy）
        DailyTick dailyTick = new DailyTick(
            gov,
            address(vault),
            address(allocation),
            address(navOracle),
            address(reserve),
            address(dividendManager),
            address(emergency),
            address(threePool)
        );

        // 9) Mock 策略
        MockStrategy strat = new MockStrategy(gov, address(vault), address(usdc));

        // 10) 多签（dry-run：3 个测试 owner，threshold 2）
        address[] memory owners = new address[](3);
        owners[0] = gov;
        owners[1] = address(0xAa10F25C0A4C2eaA0E3da39C7dcd68B4Dd7E0001);
        owners[2] = address(0xAa20f25c0a4c2eAA0e3dA39c7DCD68B4Dd7e0002);
        FundMultisig multisig = new FundMultisig(owners, 2);

        // ===== 授权与初始化（Phase 1） =====

        shareToken.setMinter(address(sub), true);
        shareToken.setBurner(address(red), true);
        sub.setRedemptionManager(address(red));

        vault.setSpender(address(sub), true);
        vault.setSpender(address(red), true);
        vault.setSpender(address(allocation), true);
        vault.setSpender(address(dailyTick), true);

        reserve.setSpender(address(dailyTick), true);
        dividendManager.setPublisher(address(dailyTick), true);

        emergency.setGuardian(gov, true);

        // NAV signers：deployer + 两个测试地址（实战换为托管/审计/Chainlink）
        navOracle.setSigner(gov, true);
        navOracle.setSigner(address(0xAa10F25C0A4C2eaA0E3da39C7dcd68B4Dd7E0001), true);
        navOracle.setSigner(address(0xAa20f25c0a4c2eAA0e3dA39c7DCD68B4Dd7e0002), true);

        // KYC：预批 deployer 与多签 owners
        kyc.approve(gov, bytes32("SG"));

        // 策略：MockStrategy 80% 权重，余 20% 留 idle
        allocation.addStrategy(address(strat), 8000, 8000);

        // 赎回费阶梯：< 90d=2%, 90-180=1%, ≥180=0
        RedemptionManager.FeeTier[] memory tiers = new RedemptionManager.FeeTier[](3);
        tiers[0] = RedemptionManager.FeeTier({maxDays: 89, bps: 200});
        tiers[1] = RedemptionManager.FeeTier({maxDays: 179, bps: 100});
        tiers[2] = RedemptionManager.FeeTier({maxDays: type(uint32).max, bps: 0});
        red.setFeeTiers(tiers);

        vm.stopBroadcast();

        // ===== 打印地址（用于写 deployments 与 .env） =====
        console2.log("=== fund-vault Arbitrum Sepolia deployment ===");
        console2.log("CHAIN_ID                    =", block.chainid);
        console2.log("USDC_ADDRESS                =", address(usdc));
        console2.log("SHARE_TOKEN_ADDRESS         =", address(shareToken));
        console2.log("SUBSCRIPTION_MANAGER_ADDRESS=", address(sub));
        console2.log("REDEMPTION_MANAGER_ADDRESS  =", address(red));
        console2.log("NAV_ORACLE_ADDRESS          =", address(navOracle));
        console2.log("ALLOCATION_MANAGER_ADDRESS  =", address(allocation));
        console2.log("DIVIDEND_MANAGER_ADDRESS    =", address(dividendManager));
        console2.log("RESERVE_FUND_ADDRESS        =", address(reserve));
        console2.log("FUND_VAULT_ADDRESS          =", address(vault));
        console2.log("FEE_ROUTER_ADDRESS          =", address(0)); // v1.1
        console2.log("EMERGENCY_CONTROLLER_ADDRESS=", address(emergency));
        console2.log("KYC_REGISTRY_ADDRESS        =", address(kyc));
        console2.log("DAILY_TICK_ADDRESS          =", address(dailyTick));
        console2.log("MULTISIG_ADDRESS            =", address(multisig));
        console2.log("THREE_POOL_POLICY           =", address(threePool));
        console2.log("KELLY_POLICY                =", address(kelly));
        console2.log("MOCK_STRATEGY               =", address(strat));
        console2.log("DEPLOYER (gov)              =", gov);
    }
}
