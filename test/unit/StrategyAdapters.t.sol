// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AdapterBase} from "src/strategies/AdapterBase.sol";
import {ActiveAlphaStrategy} from "src/strategies/ActiveAlphaStrategy.sol";
import {YieldPlusStrategy} from "src/strategies/YieldPlusStrategy.sol";
import {OnChainMacroStrategy} from "src/strategies/OnChainMacroStrategy.sol";
import {StakingMevStrategy} from "src/strategies/StakingMevStrategy.sol";
import {OptionsMmStrategy} from "src/strategies/OptionsMmStrategy.sol";
import {VentureLiquidStrategy} from "src/strategies/VentureLiquidStrategy.sol";

contract _TestUSDC is ERC20 {
    constructor() ERC20("TestUSDC", "tUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @notice 参数化测试 6 个参考策略 adapter 骨架。每个 adapter 都验证：
///         identity / deposit / withdraw / reportTotalAssets / 访问控制 / approve(vault, max)
contract StrategyAdaptersTest is Test {
    _TestUSDC internal usdc;

    address owner;
    address vault;
    address reporter;
    address mallory;

    AdapterBase[6] internal adapters;
    string[6] internal expectedNames = [
        "Active Alpha",
        "Yield+",
        "On-Chain Macro",
        "Staking & MEV",
        "Options MM",
        "Venture-Liquid"
    ];
    bytes32[6] internal expectedKeys = [
        keccak256("ACTIVE_ALPHA_V1"),
        keccak256("YIELD_PLUS_V1"),
        keccak256("ONCHAIN_MACRO_V1"),
        keccak256("STAKING_MEV_V1"),
        keccak256("OPTIONS_MM_V1"),
        keccak256("VENTURE_LIQUID_V1")
    ];

    function setUp() public {
        owner    = makeAddr("owner");
        vault    = makeAddr("vault");
        reporter = makeAddr("reporter");
        mallory  = makeAddr("mallory");
        usdc     = new _TestUSDC();

        adapters[0] = new ActiveAlphaStrategy(owner, vault, address(usdc), reporter);
        adapters[1] = new YieldPlusStrategy(owner, vault, address(usdc), reporter);
        adapters[2] = new OnChainMacroStrategy(owner, vault, address(usdc), reporter);
        adapters[3] = new StakingMevStrategy(owner, vault, address(usdc), reporter);
        adapters[4] = new OptionsMmStrategy(owner, vault, address(usdc), reporter);
        adapters[5] = new VentureLiquidStrategy(owner, vault, address(usdc), reporter);
    }

    function test_Identity_AllAdaptersHaveDistinctNamesAndKeys() public view {
        for (uint256 i = 0; i < 6; i++) {
            assertEq(adapters[i].strategyName(), expectedNames[i]);
            assertEq(adapters[i].strategyKey(), expectedKeys[i]);
            assertEq(adapters[i].baseAsset(), address(usdc));
            assertEq(adapters[i].vault(), vault);
            assertEq(adapters[i].reporter(), reporter);
            assertEq(adapters[i].totalAssets(), 0);
        }
    }

    function test_VaultApprovalIsMax_ForAll() public view {
        for (uint256 i = 0; i < 6; i++) {
            assertEq(usdc.allowance(address(adapters[i]), vault), type(uint256).max);
        }
    }

    function test_Deposit_IncreasesTotalAssets_OnlyVault() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(vault);
            adapters[i].deposit(1_000e6);
            assertEq(adapters[i].totalAssets(), 1_000e6);
        }
    }

    function test_Deposit_RevertsForNonVault() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(mallory);
            vm.expectRevert(AdapterBase.NotVault.selector);
            adapters[i].deposit(500e6);
        }
    }

    function test_Withdraw_DecreasesTotalAssets_OnlyVault() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.startPrank(vault);
            adapters[i].deposit(2_000e6);
            adapters[i].withdraw(800e6);
            vm.stopPrank();
            assertEq(adapters[i].totalAssets(), 1_200e6);
        }
    }

    function test_Withdraw_RevertsForNonVault() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(vault);
            adapters[i].deposit(1_000e6);
            vm.prank(mallory);
            vm.expectRevert(AdapterBase.NotVault.selector);
            adapters[i].withdraw(100e6);
        }
    }

    function test_Withdraw_RevertsWhenExceedsTotal() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(vault);
            adapters[i].deposit(500e6);
            vm.prank(vault);
            vm.expectRevert();
            adapters[i].withdraw(501e6);
        }
    }

    function test_ReportTotalAssets_UpdatesValue_OnlyReporter() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(vault);
            adapters[i].deposit(1_000e6);
            // 链下报告：策略产生 12% 盈利
            vm.prank(reporter);
            adapters[i].reportTotalAssets(1_120e6);
            assertEq(adapters[i].totalAssets(), 1_120e6);
        }
    }

    function test_ReportTotalAssets_RevertsForNonReporter() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(mallory);
            vm.expectRevert(AdapterBase.NotReporter.selector);
            adapters[i].reportTotalAssets(999e6);
        }
    }

    function test_SetReporter_OnlyOwner() public {
        address newReporter = makeAddr("newReporter");
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(mallory);
            vm.expectRevert();
            adapters[i].setReporter(newReporter);

            vm.prank(owner);
            adapters[i].setReporter(newReporter);
            assertEq(adapters[i].reporter(), newReporter);
        }
    }

    function test_VentureLiquid_LockupAndWhitelist_OnlyOwner() public {
        VentureLiquidStrategy v = VentureLiquidStrategy(address(adapters[5]));

        vm.prank(mallory);
        vm.expectRevert();
        v.setLockup(uint64(block.timestamp + 365 days));

        vm.prank(owner);
        v.setLockup(uint64(block.timestamp + 365 days));
        assertEq(v.lockupUntil(), uint64(block.timestamp + 365 days));

        address tok = makeAddr("earlyToken");
        vm.prank(owner);
        v.setWhitelist(tok, true);
        assertTrue(v.isWhitelisted(tok));
    }
}
