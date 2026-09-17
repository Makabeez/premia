# PREMIA — measured findings

All numbers produced by `script/backtest.py` (no auth, no wallet, ~40 s) and by direct
`eth_call` against Perpl on Monad mainnet. Nothing here is asserted from memory.

## 1. Trustless settlement — CONFIRMED

Perpl's exchange proxy `0x34B6552d57a35a1D042CcAe1951BD1C370112a6F` delegates to
`0xf7df187620c81deee0833589509f41f95886cd33` (EIP-1967 slot). The implementation exposes:

| Selector | Signature |
|---|---|
| `0x7dd7e759` | `getFundingSumAtBlock(uint256 marketId, uint256 block) → (int256 sum, uint256 atBlock)` |
| `0x0d3e87a7` | `getFundingInterval() → uint256` |
| `0xea3196ec` | `getPositionV2(uint256,uint256)` |
| `0x12e8eb2c` | `getAccountByAddr(address)` |

Verified live:

```
getFundingInterval()                      → 8571                    (matches docs)
getFundingSumAtBlock(1, 101137800)        → sum=-37144 atBlock=101137800
getFundingSumAtBlock(1, 101129229)        → sum=-37174 atBlock=101129229
  difference = +30                        = API `ppl` for that event exactly
getFundingSumAtBlock(1, 101137801)        → snaps down to 101137800
getFundingSumAtBlock(1, head-40,000,000)  → sum=-53080              (~194 days of history)
```

**Consequences for the design:**

1. The getter is **historical**, so series are defined by plain block heights. No activation
   race, no checkpoint keeper, no 43-minute settlement ambiguity.
2. `settle()` is callable by anyone at any time after expiry and reads the exact value.
3. It returns the event block it snapped to, so the contract derives the true interval count
   `n = (atBlockEnd − atBlockStart) / 8571` itself — the fixed leg cannot desync from the float.
4. Expiry blocks need not be aligned to the funding grid; the getter snaps down.
5. **Zero oracles, zero keepers, zero trust assumptions.** Chainlink CRE fallback dropped.

## 2. Is funding worth hedging? — YES, and my 25-day read was wrong

100 days, 2880 events per mature market:

| mkt | events | days | at clamp | mean APR | zero rate | sign flips |
|---|---|---|---|---|---|---|
| BTC | 2880 | 100 | 16.2% | **+4.70%** | 17.3% | 347 |
| MON | 2880 | 100 | 5.5% | **+11.90%** | 18.8% | 107 |
| ETH | 2880 | 100 | 7.9% | +3.20% | 18.9% | 294 |
| SOL | 1906 | 61 | 13.1% | +0.88% | 31.8% | 163 |
| HYPE | 2880 | 100 | 7.7% | **+12.13%** | 38.2% | 165 |
| ZEC | 2279 | 76 | 16.5% | **+16.65%** | 30.7% | 107 |
| LIT | 577 | 17 | 22.0% | −7.86% | 77.6% | 9 |
| PUMP | 577 | 17 | 9.7% | +5.85% | 66.9% | 6 |

The earlier 25-day BTC sample showing a mean of ≈0 was a sampling artifact: BTC flips sign
347 times in 100 days, so a short window averages to nothing while the annualised level is
+4.70%. **Correction recorded rather than quietly dropped.**

The clamp is ±40 micros (±0.004%/interval, ±48.9%/yr) on every market, and markets sit
*exactly* at it 5.5–22% of intervals. Funding is capped and frequently pinned, not quiet.

## 3. Fixed-leg pricing error — the honest limit

Naive EMA-72 forecast vs realised, in collateral per lot:

| mkt | 24h MAE/realised | 72h | 7d |
|---|---|---|---|
| ZEC | **33%** | **34%** | **34%** |
| HYPE | **41%** | **46%** | **51%** |
| MON | 44% | 53% | 74% |
| LIT | 49% | 87% | 100% |
| BTC | 68% | 85% | 97% |
| ETH | 83% | 105% | 122% |
| PUMP | 88% | 98% | 109% |
| SOL | 77% | 95% | 123% |

Read this both ways, because it cuts both ways:

- Error this large is **why the hedge has value** — funding is genuinely uncertain, so a
  trader who wants a known cost has to pay someone to take that uncertainty.
- It is also **the maker's risk**. A naive EMA quote loses money. The fixed leg needs a risk
  premium and a wide spread, not a point forecast. Improving on EMA-72 is the maker's edge and
  is not yet done.

**Product decision, measured not assumed: launch on ZEC, HYPE and MON.** Highest funding
levels *and* the most forecastable. **Exclude SOL** — 0.88% APR against 123% error is
uneconomic at any spread. BTC and ETH are the marketing markets, not the profitable ones.

## 4. Caveats

- LIT and PUMP have 17 days / 577 events. Too little to price. Excluded until n grows.
- SOL 61 days, ZEC 76 days — younger than the mature four.
- EMA-72 is a deliberately naive baseline chosen to be beatable, not a pricing model.
- `atClamp%` counts intervals at ±40 assuming 40 is the clamp. Read
  `absFundingClampPctPer100k` on-chain to confirm per market before quoting.
- Single data source (Perpl's own API), cross-checked against on-chain `getFundingSumAtBlock`
  for BTC only. Cross-check the other markets before sizing anything.
