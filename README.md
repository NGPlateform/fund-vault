# fund-vault

通用基金合约层 — 资金配置 + 分红 + 申赎 的可插拔抽象。

服务于 Manzi 系基金品牌矩阵：
- **QDFI**（三池机制：A 利息池 / B 策略池 / C 储备金）
- **F\* Capital**（凯利公式：fractional Kelly + 协方差矩阵约束）
- 任何后续基金：写一个 `ISettlementPolicy` 实例即可

## 状态

- 栈：Solidity 0.8.24 · Foundry · OpenZeppelin v5.1
- 测试：**48 / 48 通过**；line 77.7% / func 66.7%
- 部署：尚未部署（设计基线 + 测试基线，下一步：Sepolia dry-run）

## 快速上手

```bash
cd /passinger/projects/Manzi/fund-vault
export PATH="$HOME/.foundry/bin:$PATH"

forge build
forge test -vv
forge coverage --report summary
```

## 关键抽象 — ISettlementPolicy

每只基金的 daily 结算逻辑被封装为一个 `ISettlementPolicy`：

```solidity
function settle(uint64 epoch, int256 pnl, uint256 aum, uint256 reserveBal)
    external view returns (DividendPlan memory);
```

返回的 `DividendPlan` 由 `DailyTick` 协调执行（注入/支取储备 → 推入分红 → 发布 Merkle 根）。

两个参考 Policy：
- **`ThreePoolPolicy`** — QDFI 等价（6%/yr fixedYield + 30/60/10 split + 储备兜底）
- **`KellyPolicy`** — F\* Capital（无固定分红 · 1/4 Kelly · 15/60 留存）

## 合约清单（16 份）

```
src/
├── interfaces/                        # 13 份接口
├── core/                              # 12 份核心
│   ├── FundVault · ShareToken · NAVOracle
│   ├── AllocationManager · DailyTick · DividendManager
│   ├── ReserveFund · FeeRouter
│   ├── SubscriptionManager · RedemptionManager
│   └── KYCRegistry · EmergencyController
├── policies/                          # 2 份 Policy 实例
│   ├── ThreePoolPolicy.sol            # QDFI
│   └── KellyPolicy.sol                # F* Capital
├── strategies/MockStrategy.sol        # 测试适配器
├── governance/FundMultisig.sol        # K-of-N 多签
└── libraries/{DailyMath, MerkleRoots}.sol
```

## 每日 Tick 流程

```
anyEOA → DailyTick.executeDailyTick(epoch, merkleRoot)
  ├─ require: 距上次 ≥ 23h && NAV 已发布
  ├─ aum = AllocationManager.totalAssets()
  ├─ pnl = aum - lastAum
  ├─ plan = Policy.settle(epoch, pnl, aum, reserveBal)
  ├─ 处理 reserve 注入/支取
  ├─ Vault → DividendManager 推入 totalDividend
  ├─ DividendManager.publishRoot(epoch, root, total)
  └─ lastAum = aum + reserveDrawn − reserveInjected − totalDividend
```

## 测试矩阵

| Suite | Tests | Status |
|-------|-------|--------|
| KYCRegistry | 3 | ✅ |
| EmergencyController | 5 | ✅ |
| NAVOracle | 4 | ✅ |
| ThreePoolPolicy | 6 | ✅ |
| KellyPolicy | 4 | ✅ |
| FundMultisig | 5 | ✅ |
| DividendManagerClaim | 3 | ✅ |
| SubscriptionRedemption | 7 | ✅ |
| DailyFlow_ThreePool（集成）| 3 | ✅ |
| DailyFlow_Kelly（集成）| 2 | ✅ |
| FundInvariants（关键不变量）| 5 | ✅ |

## 范围（本仓库不包含）

- 审计（推荐对齐 QDFI：CertiK + Trail of Bits）
- 主网部署
- 链下 keeper 实现（Chainlink Automation / Gelato）
- Indexer/前端集成
- 真实策略适配器（仅 MockStrategy；接 CEX/DeFi 需独立实现）
- 跨链桥（LayerZero / CCIP）
- FeeRouter 与 DailyTick 的集成（FeeRouter 已实现接口与状态；DailyTick 集成留至 v1.1）

## 相关

- 现有 QDFI 合约：`../qdf-contracts/`（Hardhat、Sepolia 已部署、审计包就绪）
- 设计与不变量详解：`./DESIGN.md`
