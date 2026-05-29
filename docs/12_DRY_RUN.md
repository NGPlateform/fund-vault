# 12 · Fund-Vault Sepolia Dry-Run（里程碑）

> **日期**：2026-05-27（Arbitrum Sepolia · chainId 421614）  
> **状态**：✅ 端到端全链路链上链下双写一致  
> **目标**：用真实链上交易验证 `fund-vault` 合约层 + `qdf-platform` 索引器 + SDK 集成的完整闭环

## 1. 范围与里程碑意义

本次 dry-run 是 **从合约 → 索引器 → DB 投影** 的首个端到端验证，覆盖 fund-vault 设计的核心生命周期：

```
deploy (17 合约)
   → KYC.Approved
       → NAVOracle.NAVPublished (epoch 1, bootstrap)
           → SubscriptionManager.Subscribed (100k USDC → 100k FUSF)
               → AllocationManager.rebalance() (vault → strategy 80%)
                   → MockStrategy 模拟 +1000 USDC 盈利
                       → NAVOracle.NAVPublished (epoch 2, nav 1.01e18)
                           → DailyTick.executeDailyTick(epoch=2)
                                ├─ vault → ReserveFund: 98.34 USDC
                                ├─ vault → DividendManager: 16.60 USDC
                                ├─ TickExecuted event
                                └─ DividendManager.RootPublished
                                    → DividendManager.claim → 持有人到账 16.60 USDC
```

**每一步**都在链上落地为真实交易，**且**被 `qdf-platform` 索引器实时拉取、解码并写入 Postgres，
最终的链下投影（`Subscription` / `NavSnapshot` / `DividendRound` / `DividendRecord` / `Account` /
`AuditLog`）与链上事实**完全一致**。

## 2. 部署清单（Arbitrum Sepolia · chainId 421614）

完整 JSON：`fund-vault/deployments/arbitrumSepolia.json`

| 合约 | 地址 | 用途 |
|------|------|------|
| MockUSDC | `0xa95b2e18Cabb46097Da0F19FDa919Dc947487822` | 基础资产（Sepolia 无真实 USDC） |
| ShareToken (FUSF) | `0xbA5BC302cDd203263b168f2F54fbf724a591f56d` | 份额代币（KYC-gated transfer） |
| SubscriptionManager | `0x44e4CA93C6c7a1DbAEf6CF73fdEdE84Be6be4978` | 申购 + 锁定期 |
| RedemptionManager | `0x525d61cbF0BD47bd07588Cc7bf99526344C9f359` | 同步赎回 + 阶梯赎回费 |
| NAVOracle | `0x0A0C78F67977C0A0AB711D03Aa343622Bd1D0f63` | 2/3 多签 NAV |
| AllocationManager | `0x04D0475b02Afd23DD7D5b036a9e863162c0c34B0` | N 策略权重 + rebalance |
| DividendManager | `0x60dAA71A775aF9c757a22392E884734bC39dBcB1` | Merkle 根 + 持有人领取 |
| ReserveFund | `0xEdE7552aB7A771Cdb46ce45dE2624443FB10995E` | 储备金 |
| FundVault | `0x6c4269Dd0B19082A5D9Ce98C4803bD6f6502D4D4` | USDC 唯一托管 |
| EmergencyController | `0xe3A9B9A7A1b15fd8b9FB835E56EB78f618a868Ca` | 守护人熔断 |
| KYCRegistry | `0x8Ea48Fce1aDF4121881C330F85dc10a88937351C` | 地址白名单 |
| DailyTick | `0xE09ed75E8259FEdcDAe6a1112bBbeD45b7C2Cd7b` | 每日结算协调 |
| FundMultisig | `0x2CDf6Fc04f75BCF408c9654BDBCDB42B7272f27A` | K-of-N 多签（3/2，dry-run 期未启用治理） |
| ThreePoolPolicy | `0xc835Eedf3Eb527dd4854612d95fa0AE0A3a7B253` | QDFI 等价结算 Policy（**默认启用**） |
| KellyPolicy | `0x73c5609f39A04E5DBE811eE7f635D359971bC4be` | F\* Capital 凯利 Policy（备用） |
| MockStrategy | `0x61279F5213A19F2d84CD819549476D470c982f1C` | 测试策略（手动 setPnL 模拟盈亏） |
| Deployer / gov | `0x0CaEDdC94251F6Cf4E726eCB0A50C27f47738ce7` | 部署者，所有合约 owner |

**Gas 消耗（部署）**：~0.0007 ETH

## 3. 参数快照

| 维度 | 值 |
|------|---|
| 最低申购 | 1,000 USDC |
| 锁定期 | 30 天（2,592,000 s） |
| NAV 阈值 | 2/3 签名 · ±20% 偏离上限 |
| 赎回费阶梯 | <90d: 200 bps · 90-180d: 100 bps · ≥180d: 0 |
| 三池参数 | 6%/yr fixed · 30/60/10 split · cap 25% · floor 5% |
| Kelly 参数 | 1/4 Kelly · 15/60 留存 · cap 25% · floor 5% |
| 策略权重 | MockStrategy 80%（留 20% idle 给每日动作） |
| NAV 签名人 | 4 个（deployer + 2 占位 + PK2 实际签名用） |

## 4. 执行轨迹（按 block 顺序）

| Block | Action | Tx Hash 前缀 | 链上效果 | indexer 解析的 args（精简） |
|---|---|---|---|---|
| 271450079 | 部署 SubscriptionManager | — | — | `MinSubscriptionSet{amount:1000000000}` `LockupSet{secs:2592000}` |
| 271450105 | 部署 DailyTick | — | — | `PolicySet{policyId:0x7a67…}` |
| 271450176-183 | NAVOracle.setSigner × 3 | — | — | `SignerSet × 3` |
| 271450188 | KYCRegistry.approve(deployer) | `0xa3b047…` | KYC 通过 | `Approved{account:deployer, jurisdictionCode:"SG"}` |
| 271450204 | RedemptionManager.setFeeTiers | — | — | `FeeTierSet × 3` |
| 271450664 | KYCRegistry.approve(0x1111…) | `0xf0b422…` | KYC 烟测 | `Approved{account:0x1111…, jurisdictionCode:"SG"}` |
| 271458464 | NAVOracle.setSigner(PK2) | `0x730fee…` | 加入有 PK 的签名人 | `SignerSet{signer:0x17c5…d025, active:true}` |
| 271458543 | NAVOracle.publish(epoch=1) | `0x469e86…` | bootstrap NAV | `NAVPublished{epoch:1, nav:1e18, totalAssets:0, totalSupply:0}` |
| 271459769 | SubscriptionManager.subscribe(100k) | `0xea69fd…` | mint 100k FUSF · USDC 入 vault · 30d 锁定 | `Subscribed{account:deployer, amount:100k, shares:100k, navUsed:1e18, unlockAt:2026-06-26}` |
| 271461023 | AllocationManager.rebalance() | — | vault 80k → strategy | （内部 `DeployedToStrategy`） |
| 271461075 | DailyTick.setLastAum(100k) | — | 锚定 PnL 基准 | — |
| 271461140 | MockStrategy.setPnL(+1k) | — | strat 余额 80k → 81k | — |
| 271461268 | NAVOracle.publish(epoch=2) | — | NAV 升 1.01e18 | `NAVPublished{epoch:2, nav:1.01e18, totalAssets:101k, totalSupply:100k}` |
| 271461343 | DailyTick.executeDailyTick(2, root) | `0xa2c3ae…` | 三池结算 + 派分红 | `PayoutRequested × 2` · `TickExecuted{pnl:1k, aum:101k, totalDividend:16.60, root}` · `RootPublished{epoch:2, total:16.60}` |
| 271463096 | DividendManager.claim(2, …) | `0x5d4dd2…` | 16.60 USDC 到 deployer | `Claimed{epoch:2, account:deployer, amount:16602739}` |

## 5. 关键结算数学（ThreePoolPolicy 验证）

输入：AUM = 101,000 USDC · PnL = +1,000 USDC · reserveBal = 0

| 项 | 计算 | 结果 | 链上读取 |
|---|---|---|---|
| fixed = AUM × 6% / 365 | 101,000 × 0.06 / 365 | 16.60 USDC | `totalAt(2) = 16,602,739` ✓ |
| profit-after-fixed | 1,000 − 16.60 | 983.40 USDC | — |
| floatSuspended | reserveBal (0) < AUM × 5% (5,050) | **true** | （触发） |
| float（暂停） | 0 | 0 | `floatDividend` = 0 ✓ |
| reserveInjected | 983.40 × 10% | 98.34 USDC | Reserve 余额 = 98,339,726 ✓ |
| toNAV | 983.40 × 60% + suspended float (983.40 × 30%) | ~885 USDC | （留 vault/strategy 资产中） |
| totalDividend | fixed + float | 16.60 USDC | DividendManager 收到 ✓ |
| lastAum (next) | AUM + reserveDrawn − reserveInjected − totalDividend | 100,885.06 USDC | `lastAum = 100,885,057,535` ✓ |

所有数学项与链上读数 **完全一致**。

## 6. 链下投影对账（Postgres）

| 表 | 行数 | 校验点 |
|----|------|--------|
| `ChainEvent` | 17 | 包含 5 类业务事件（Subscribed/NAVPublished/Approved/TickExecuted/RootPublished/Claimed/PayoutRequested + 部署期初始化事件） |
| `Subscription` | 1 | amountIn=100k, sharesIssued=100k, status=Settled, lockupEndsAt=2026-06-26 |
| `NavSnapshot` | 2 | epoch=1 (nav=1e18, AUM=0) · epoch=2 (nav=1.01e18, AUM=101k) |
| `DividendRecord` | 1 | epoch=2, totalDividend=16.60, status=Paid |
| `Account` | 1 | shareBalance=100k · totalSubscribedUSDC=100k · totalDividendReceived=16.60 |
| `AuditLog` | 2 | `DAILY_TICK_EXECUTED` + `DIVIDEND_ROOT_PUBLISHED`（不可变锚点） |
| `Investor` | 2 | deployer + 烟测地址 0x1111… |

## 7. 期间发现并修复的问题

### 7.1 Indexer 缺乏幂等性 → 投影翻倍

**症状**：`Account.shareBalance` 显示 200,000 FUSF（应为 100,000）—— 申购事件被 indexer 重组回看
窗口（`REORG_LOOKBACK_BLOCKS=10`）多扫一次，handler 内的 `increment` 被运行两次。

**根因**：`ChainEvent` 的复合唯一约束 `(chainId, txHash, logIndex)` 阻止重复行，但
`db.account.update({ shareBalance: { increment: amount } })` 等 **副作用** 不幂等。

**修复**（`qdf-platform/src/chain-indexer/dispatcher.ts`）：
```ts
const existing = await db.chainEvent.findUnique({ where: { chainId_txHash_logIndex: {...} } });
if (existing) {
  // 仅 refresh blockHash/status；不再触发 handler
  await persistChainEvent(db, ctx, args);
  return;
}
await db.$transaction(async (tx) => {
  await persistChainEvent(tx, ctx, args);
  if (handler) await handler(tx, ctx, args);
});
```

修复后重启 indexer 跑多轮（cursor 反复回看包含申购的区间），`Account.shareBalance` 稳定为 100k。

### 7.2 KYC handler 误用不存在的 Prisma 字段

**症状**：`handleKYCApproved` 写 `Investor.kycStatus` / `kycJurisdiction` 字段，但实际 schema 把
KYC 详情放在独立的 `KycRecord` 模型；`prisma db push` 后这两个字段不存在 → indexer 抛
`Unknown argument 'kycStatus'`。

**修复**（`src/chain-indexer/handlers.ts`）：handler 仅确保 `Investor` 行存在（`upsert with empty update`），
完整的 KYC 状态同步走管理 API + `KycRecord`，不在链上事件 handler 里做。

## 8. dry-run 期间未触及的能力

| 能力 | 原因 |
|------|------|
| 30 天锁定后赎回 | Sepolia 不能 `vm.warp`；要等真实时间或重新部署 lockup=0 |
| KellyPolicy 实证 | DailyTick 当前指向 ThreePoolPolicy；可经 `setPolicy(kelly)` 切换 |
| FeeRouter 接入 | 接口/状态已写，DailyTick 集成留至 v1.1 |
| FundMultisig 接管治理 | dry-run 期间 gov = deployer EOA；多签接管未做 |
| 多 holder Merkle 树 | 当前只 1 个持有人，Merkle 根 = leaf；多人场景需 indexer 端配合生成 |

## 9. 复现命令（任何环境）

```bash
# 1) 部署
cd fund-vault
export PATH="$HOME/.foundry/bin:$PATH"
export DEPLOYER_KEY=$(grep ^DEPLOYER_KEY= ../qdf-contracts/.env | cut -d= -f2)
export RPC=$(grep ^ARBITRUM_SEPOLIA_RPC_URL= ../qdf-contracts/.env | cut -d= -f2)
forge script script/DeploySepolia.s.sol:DeploySepolia --rpc-url "$RPC" --broadcast --slow

# 2) Indexer
cd ../qdf-platform
docker run -d --name qdf-postgres-dev -p 5432:5432 \
  -e POSTGRES_USER=qdf -e POSTGRES_PASSWORD=qdf -e POSTGRES_DB=qdf_platform postgres:16
set -a; source .env.local; set +a
npx prisma generate && npx prisma db push
npm run indexer

# 3) 触发流程（按 4. 执行轨迹的顺序）
#    详见 docs/12_DRY_RUN.md §4 与 fund-vault/deployments/arbitrumSepolia.json
```

## 10. 下一步建议（v1.1 路线）

1. **FeeRouter 接入 DailyTick** —— accrue 管理费/业绩费的真正写入路径
2. **多 holder 端到端** —— indexer 端生成 Merkle 树（持有人 × 当日权重）+ DividendLeaf 表
3. **真实策略适配器** —— Aave / Pendle / Coinbase Cloud Staking 适配器替换 MockStrategy
4. **FundMultisig 接管** —— 把所有合约的 owner 从 deployer 转移到 multisig，设定 Timelock 延迟
5. **审计准备** —— 对齐 QDFI 的 CertiK + Trail of Bits 标准送审

## 相关

- 设计：`fund-vault/DESIGN.md`
- 合约层 README：`fund-vault/README.md`
- 部署地址：`fund-vault/deployments/arbitrumSepolia.json`
- 平台 SDK：`qdf-platform/src/lib/fund-vault.ts`
- Indexer：`qdf-platform/src/chain-indexer/`
