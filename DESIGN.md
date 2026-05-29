# DESIGN — fund-vault

## 0. 目标与非目标

**目标**：把"资金配置 + 分红"做成可被多只基金共用、生命周期完整、可审计的智能合约层。
基金的差异（QDFI 三池 / F\* Capital 凯利 / …）通过部署不同的 `ISettlementPolicy` 实例来表达，
其余资产、价格、申赎、治理基础设施完全复用。

**非目标**：
- 不是 vault aggregator（不模仿 Yearn / Beefy）；
- 不试图链上跑量化策略；策略本身在链下（Trading systems），链上只做托管 + 配置 + 分红；
- 不解决 KYC 流程本身（只在链上维护白名单）。

## 1. 实体与信任假设

| 实体 | 链上 | 链下 |
|------|------|------|
| 持有人 Holder | 持 ShareToken；申购 / 赎回 / 领取分红 | KYC 流程 |
| 治理 Governance | `FundMultisig` (K-of-N) + Timelock | 多签人钥匙 |
| 守护人 Guardian | `EmergencyController.pause()` | 监控告警 |
| NAV 签名人 | `NAVOracle` 签发 daily NAV | 托管/审计/Chainlink |
| Keeper | 任何 EOA 可触发 `DailyTick` | Chainlink Automation / Gelato |
| Strategy Operator | 链下下单 → IStrategy 适配器 | CEX/DEX/staking |

**信任最小化**：
- Vault 不持有除 baseAsset 以外的任何资产；
- 资金外流必须经 `requestPayout` + 授权 spender；
- 治理参数变更经 K-of-N + Timelock；
- 紧急熔断由独立 Guardian 触发，恢复必须经治理。

## 2. 状态机：每日 Tick

```
            ┌────────────────────────────────────────────┐
            │ DailyTick.executeDailyTick(epoch, root)    │
            └────────────────────────────────────────────┘
                              │
       ┌──────────────────────┼──────────────────────┐
       │                      │                      │
       ▼                      ▼                      ▼
   isPaused?            block.timestamp        NAVOracle.
   = false              ≥ last + 23h           epochPosted(epoch)
   else REVERT          else REVERT            = true else REVERT
                              │
                              ▼
                aum = AllocationManager.totalAssets()
                              │
                              ▼
                pnl = int(aum) - int(lastAum)
                              │
                              ▼
                plan = Policy.settle(epoch, pnl, aum, reserveBal)
                              │
       ┌──────────────────────┼──────────────────────┐
       ▼                      ▼                      ▼
   plan.reserveInjected   plan.reserveDrawn    plan.totalDividend
   > 0:                   > 0:                 > 0:
   vault →                reserve →            vault →
   reserve                vault                DividendManager
                              │
                              ▼
                DividendManager.publishRoot(epoch, root, plan.totalDividend)
                              │
                              ▼
                lastAum = aum + reserveDrawn - reserveInjected - totalDividend
                lastEpoch = epoch
                lastTickAt = block.timestamp
```

## 3. ISettlementPolicy 语义

`settle()` 是**纯函数**——它读取 `(epoch, pnl, aum, reserveBal)` 输出 `DividendPlan`，不修改状态。
这让 Policy 可在审计时被独立分析，并允许 fuzz/property testing 直接对 Policy 输入扫描。

```solidity
struct DividendPlan {
    uint256 fixedDividend;
    uint256 floatDividend;
    uint256 totalDividend;      // = fixedDividend + floatDividend
    uint256 toNAV;
    uint256 reserveInjected;
    uint256 reserveDrawn;
    bool    floatSuspended;
    bytes   policyData;         // policy-specific extension
}
```

**核心 invariant**（Policy 的契约）：
1. `totalDividend == fixedDividend + floatDividend`
2. `reserveInjected == 0 || reserveDrawn == 0`（同日不可既注入又支取）
3. `reserveInjected <= max(0, pnl)`（注入只来源于盈利）
4. `reserveDrawn <= reserveBal`（支取不超过余额）
5. `floatSuspended == true` ⇒ `floatDividend == 0`

### 3.1 `ThreePoolPolicy`（QDFI 等价）

参数：`{fixedYieldBpsYear, floatBps, toNAVBps, reserveInjectBps, reserveCapBps, reserveFloorBps}`
约束：`floatBps + toNAVBps + reserveInjectBps == 10000`。

```
fixed = aum * fixedYieldBpsYear / 10000 / 365

if pnl >= 0:
    fromProfitForFixed = min(profit, fixed)
    fromReserveForFixed = pnl < fixed ? (fixed - fromProfitForFixed) : 0
    remain = profit - fromProfitForFixed
    inject = remain * reserveInjectBps / 10000  (clamped by cap)
    float  = floatSuspended ? 0 : remain * floatBps / 10000
    nav    = remain * toNAVBps / 10000 + (cap overflow) + (suspended float)
else:
    fixed_actual = min(fixed, reserveBal)
    drawn = fixed_actual
    float, nav = 0, 0
```

### 3.2 `KellyPolicy`（F\* Capital）

参数：`{kellyFractionBps, reserveInjectBps, toNAVBps, reserveCapBps, reserveFloorBps}`
约束：三比例之和 == 10000；亏损日**不发**任何分红（避开"保收益"承诺）。

```
fixed = 0
if pnl <= 0:
    return zero plan (除 floatSuspended 标记)
else:
    inject = pnl * reserveInjectBps / 10000  (clamped by cap)
    float  = floatSuspended ? 0 : pnl * kellyFractionBps / 10000
    nav    = pnl * toNAVBps / 10000 + overflow + suspended float
```

## 4. 安全设计

### 4.1 重入

- 所有外部资金动作使用 `nonReentrant`（OZ ReentrancyGuard）。
- 跨合约调用顺序：先检查 → 后更新状态 → 后转账（CEI 模式）。

### 4.2 访问控制

- `Ownable`：所有 admin 接口由 owner（= `FundMultisig` 通过 Timelock）调用。
- spender 模式：FundVault / ReserveFund 的资金动作仅授权 spender 可触发，
  这些 spender 是核心合约（DailyTick / SubscriptionManager / RedemptionManager / AllocationManager）。
- 守护人独立于 owner：可单独 `pause()`，但 `unpause()` 必须经 owner。

### 4.3 时间防御

- `DailyTick` 强制 `minIntervalSecs` 间隔，防止短时间内多次结算扰动 NAV。
- `NAVOracle` 强制 `epoch` 严格递增 + 偏离上限（默认 ±20%），避免极端价格突击。

### 4.4 KYC 边界

- `ShareToken._update` 钩子：用户间转账要求双方 KYC，mint/burn 不要求（由 SubscriptionManager 在
  申购入口处把关，Redemption 仅销毁不需要校验）。

### 4.5 资产守恒（不变量）

1. `vault.idle + sum(strategy.totalAssets) == AllocationManager.totalAssets()`
2. `reserveBal == ReserveFund.balance()`，独立于 vault 余额
3. 总系统价值 ≥ ShareToken.totalSupply × initialPrice（无外部资金注入时增长仅来自正 PnL）
4. `sum(strategy.targetBps) <= 10000`

## 5. 已知边界与下一步

| 边界 | 说明 |
|------|------|
| FeeRouter 未接入 DailyTick | 接口与状态已实现，v1.1 计划接入：DailyTick 在 settle 后调用 `feeRouter.accrueManagement(epoch, aum)` |
| 高水位线 | FeeRouter.performanceFee 需 HWM 维护；当前由 owner setHighWaterMark 手动；v1.1 与 NAVOracle 联动 |
| 跨链 | 当前合约单链部署；多链复制需独立部署一套 |
| 真实策略适配器 | 仅 MockStrategy；接 Aave/Pendle/CEX 需另一仓库实现 IStrategy |
| Merkle 树生成 | DividendManager 只验证根；树由链下生成（按持有人 × 每股分红）— 需独立 indexer 服务 |
| Timelock | 当前未实现专用合约；建议直接部署 OZ TimelockController 并把 owner 设为 Timelock 地址 |

## 6. 部署清单（参考流程）

1. 部署 `MockUSDC`（mainnet 用真实 USDC 地址）
2. `KYCRegistry(gov)`
3. `EmergencyController(gov)`，再 `setGuardian(...)`
4. `ShareToken("F-Star Fund Share","FUSF",6,gov,kyc)`
5. `NAVOracle(gov, threshold=2, maxDeviation=2000)`，再 `setSigner(...)`
6. `FundVault(gov, usdc)`
7. `AllocationManager(gov, vault)`；`addStrategy(...)`
8. `ReserveFund(gov, usdc)`
9. `DividendManager(gov, usdc)`
10. `ThreePoolPolicy(gov, params)` 或 `KellyPolicy(gov, params)`
11. `SubscriptionManager(...)`、`RedemptionManager(...)`
12. `DailyTick(gov, ..., policy)`
13. 全部 `setSpender(...)` / `setMinter(...)` / `setBurner(...)` / `setPublisher(...)` 授权
14. 把全部 `owner` 转给 `FundMultisig`（建议先 Timelock 一层）

## 7. 与 qdf-contracts 的关系

- `qdf-contracts/` 是 QDFI 专用、Hardhat 栈、已部署 Sepolia、审计包就绪的实现。
- `fund-vault/` 是泛化、Foundry 栈、未部署的下一代实现。
- 二者**并存**：QDFI 暂时保持现有 Sepolia 部署；新发的基金（F\* Capital 等）从 `fund-vault` 部署。
- 后续若 QDFI 决议迁移，可重新部署一套 `ThreePoolPolicy` 实例并通过 ShareToken 兑换。
