#!/usr/bin/env bash
# PREMIA bootstrap — writes the full repo into the current directory.
#   bash premia-setup.sh
set -euo pipefail

echo "==> writing files into $(pwd)"
mkdir -p src/interfaces src/lib test script

cat > .gitignore <<'PREMIA_EOF'
out/
cache/
lib/
node_modules/
.env
broadcast/
PREMIA_EOF

cat > foundry.toml <<'PREMIA_EOF'
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc = "0.8.30"
optimizer = true
optimizer_runs = 200

[rpc_endpoints]
monad = "https://rpc.monad.xyz"
PREMIA_EOF

cat > README.md <<'PREMIA_EOF'
# PREMIA

**Lock your funding bill in dollars.** Funding swaps on [Perpl](https://perpl.xyz), the perps
DEX on Monad.

A trader holding a perp position pays funding they cannot predict. PREMIA lets them pay a fixed
amount instead, and hands the uncertainty to someone who wants it.

## Why this is not another oracle product

Perpl settles funding through a cumulative accumulator stored on-chain per market. The exchange
exposes it historically:

```solidity
getFundingSumAtBlock(uint256 marketId, uint256 blockNumber)
    returns (int256 sum, uint256 atBlock)
```

Funding owed by a position of `L` lots between two blocks is exactly `(sum_b - sum_a) * L`.

So the floating leg of a PREMIA swap is not an *estimate* of what funding did. It is the
identical number the trader's own position was charged. **The hedge has zero basis by
construction** — something no centralised funding swap can offer, because no centralised venue
publishes its funding accrual as readable state.

Consequences: no oracle, no keeper, no price feed, no trusted reporter. Settlement is a pure
view call, callable by anyone, at any time after expiry.

| | |
|---|---|
| Perpl proxy | `0x34B6552d57a35a1D042CcAe1951BD1C370112a6F` |
| Implementation | `0xf7df187620c81deee0833589509f41f95886cd33` |
| Chain | Monad mainnet, id 143 |
| Funding interval | 8571 blocks (~43 min) |
| Collateral | AUSD |

## Verify it yourself

```bash
forge test --match-contract FundingReaderForkTest -vv
```

Seven assertions against live mainnet state, including the one the instrument rests on: the
accumulator delta across one interval equals the per-lot payment Perpl's own API reports.

```bash
python3 script/backtest.py
```

100 days of funding across all 8 Perpl markets. No wallet, no key, ~40 s. Produces the numbers
in [BENCHMARKS.md](./BENCHMARKS.md).

## What the data says

Funding on Perpl is real, capped, and hard to forecast:

- ZEC **+16.65%** APR, HYPE **+12.13%**, MON **+11.90%**, BTC **+4.70%** over 100 days
- the rate is clamped at ±40 micros and sits *exactly* at the clamp 5.5–22% of intervals
- a naive EMA-72 forecast misses realised funding by 33–123%

That error is the reason the hedge is worth buying, and equally the reason the maker needs a
risk premium rather than a point forecast. Launch markets are **ZEC, HYPE, MON** — highest
funding and lowest forecast error. SOL is excluded: 0.88% APR against 123% error is uneconomic
at any spread.

## Status

Built for [Metropolis](https://www.monad.xyz/developers/hackathons/metropolis) (Monad),
Onchain Finance & Trading.

- [x] Trustless settlement path verified on mainnet
- [x] 100-day backtest, market selection
- [ ] Swap contract + on-chain quote book
- [ ] Mobile client (React Native + Mera passkey accounts + AUSD)
- [ ] Maker bot

## Licence

MIT
PREMIA_EOF

cat > BENCHMARKS.md <<'PREMIA_EOF'
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
PREMIA_EOF

cat > src/interfaces/IPerplExchange.sol <<'PREMIA_EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Perpl exchange on Monad mainnet.
/// Proxy  0x34B6552d57a35a1D042CcAe1951BD1C370112a6F
/// Impl   0xf7df187620c81deee0833589509f41f95886cd33  (EIP-1967)
///
/// Selectors confirmed by scanning the implementation bytecode and resolving
/// against the public signature database, then exercised live via eth_call.
/// Return shapes are decoded from raw returndata — re-confirm against verified
/// source if Perpl publishes it.
interface IPerplExchange {
    /// @notice Cumulative funding product for a market, at the last funding
    ///         event at or before `blockNumber`.
    /// @dev    selector 0x7dd7e759. Returns the sum and the funding-event block
    ///         it snapped down to, so callers never need grid-aligned inputs.
    ///         Funding owed by a position of L lots between two blocks is
    ///         (sum_b - sum_a) * L, in collateral units per lot.
    function getFundingSumAtBlock(uint256 marketId, uint256 blockNumber)
        external view returns (int256 sum, uint256 atBlock);

    /// @notice Blocks between funding events. 8571 on mainnet (~2580s).
    /// @dev    selector 0x0d3e87a7
    function getFundingInterval() external view returns (uint256);

    /// @dev selector 0x12e8eb2c
    function getAccountByAddr(address account) external view returns (uint256);
}
PREMIA_EOF

cat > src/lib/FundingReader.sol <<'PREMIA_EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPerplExchange} from "../interfaces/IPerplExchange.sol";

/// @title FundingReader
/// @notice Reads realised Perpl funding straight out of the exchange that
///         charged it. No oracle, no keeper, no reported price.
///
/// This is the whole trust story of PREMIA: the floating leg of a swap is not
/// an estimate of funding, it is the identical accumulator the trader's perp
/// position is settled against. A hedge built on it has zero basis by
/// construction.
library FundingReader {
    error WindowNotElapsed(uint256 startBlock, uint256 endBlock);
    error NoFundingData(uint256 marketId, uint256 blockNumber);

    /// @notice Realised funding per lot over a block window, and the number of
    ///         funding intervals actually spanned.
    /// @dev    Both endpoints snap down to the last funding event at or before
    ///         the given block, so `intervals` is derived from what the chain
    ///         actually recorded rather than from nominal calendar maths. A
    ///         fixed leg priced off `intervals` therefore cannot desync from
    ///         the floating leg, however late settlement is called.
    /// @return perLot   signed collateral per lot; positive means longs paid
    /// @return intervals funding events spanned
    function accrual(
        IPerplExchange exchange,
        uint256 marketId,
        uint256 startBlock,
        uint256 endBlock
    ) internal view returns (int256 perLot, uint256 intervals) {
        if (endBlock <= startBlock) revert WindowNotElapsed(startBlock, endBlock);

        (int256 s0, uint256 b0) = exchange.getFundingSumAtBlock(marketId, startBlock);
        (int256 s1, uint256 b1) = exchange.getFundingSumAtBlock(marketId, endBlock);

        if (b0 == 0) revert NoFundingData(marketId, startBlock);
        if (b1 == 0) revert NoFundingData(marketId, endBlock);

        perLot = s1 - s0;
        intervals = b1 > b0 ? (b1 - b0) / exchange.getFundingInterval() : 0;
    }
}
PREMIA_EOF

cat > test/FundingReader.fork.t.sol <<'PREMIA_EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IPerplExchange} from "../src/interfaces/IPerplExchange.sol";
import {FundingReader} from "../src/lib/FundingReader.sol";

/// Every assertion below was first observed via raw eth_call against Monad
/// mainnet. If Perpl upgrades the implementation and these break, the swap's
/// settlement assumptions have changed and PREMIA must not be deployed until
/// they are re-derived.
contract FundingReaderForkTest is Test {
    using FundingReader for IPerplExchange;

    IPerplExchange constant PERPL =
        IPerplExchange(0x34B6552d57a35a1D042CcAe1951BD1C370112a6F);

    uint256 constant BTC = 1;
    uint256 constant ETH = 20;

    // Two adjacent BTC funding events.
    uint256 constant FEB_A = 101129229;
    uint256 constant FEB_B = 101137800;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("monad"), 102579854);
    }

    function test_FundingIntervalIsDocumentedValue() public view {
        assertEq(PERPL.getFundingInterval(), 8571);
    }

    function test_SumMatchesPublicApi() public view {
        (int256 sA, uint256 bA) = PERPL.getFundingSumAtBlock(BTC, FEB_A);
        (int256 sB, uint256 bB) = PERPL.getFundingSumAtBlock(BTC, FEB_B);
        assertEq(sA, -37174);
        assertEq(sB, -37144);
        assertEq(bA, FEB_A);
        assertEq(bB, FEB_B);
    }

    /// The delta across one interval must equal the per-lot payment the API
    /// reports for that event (`ppl` = 30). This is the identity the whole
    /// instrument rests on.
    function test_DeltaEqualsPaymentPerLot() public view {
        (int256 perLot, uint256 intervals) =
            PERPL.accrual(BTC, FEB_A, FEB_B);
        assertEq(perLot, 30);
        assertEq(intervals, 1);
    }

    /// Non-aligned blocks snap down to the previous funding event, so series
    /// can expire at any block height.
    function test_UnalignedBlockSnapsDown() public view {
        (int256 s, uint256 b) = PERPL.getFundingSumAtBlock(BTC, FEB_B + 1);
        assertEq(s, -37144);
        assertEq(b, FEB_B);
    }

    /// History reaches far enough back that no realistic swap tenor can fall
    /// off the end.
    function test_DeepHistoryAvailable() public view {
        (, uint256 b) = PERPL.getFundingSumAtBlock(BTC, 62579854);
        assertGt(b, 0);
    }

    function test_FundingCanBePositive() public view {
        (int256 s,) = PERPL.getFundingSumAtBlock(ETH, FEB_B);
        assertEq(s, 1600);
    }

    function test_RevertsOnInvertedWindow() public {
        vm.expectRevert();
        this.accrualExternal(BTC, FEB_B, FEB_A);
    }

    function accrualExternal(uint256 m, uint256 a, uint256 b)
        external view returns (int256, uint256)
    {
        return PERPL.accrual(m, a, b);
    }
}
PREMIA_EOF

cat > script/backtest.py <<'PREMIA_EOF'
#!/usr/bin/env python3
"""PREMIA backtest: is Perpl funding worth hedging?
Pulls full funding history per market from the public Perpl API and answers:
  1. what fraction of intervals sit at the clamp (rate suppressed, not quiet)
  2. what a fixed leg would have cost vs realised, per tenor
No auth, no wallet. Run: python3 backtest.py
"""
import json, urllib.request, time, statistics as st

API = "https://app.perpl.xyz/api"
MARKETS = {1:"BTC",10:"MON",20:"ETH",31:"SOL",40:"HYPE",50:"ZEC",60:"LIT",90:"PUMP"}
DAYS = 90

HDRS = {"User-Agent": "premia-backtest/0.1", "Accept": "application/json"}

def get(url):
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers=HDRS)
            return json.load(urllib.request.urlopen(req, timeout=30))
        except Exception as e:
            if i == 2: print("  !", url[-40:], e)
            time.sleep(1.5*(i+1))
    return None

def history(mid, days=DAYS):
    """Walk backwards in <=25d windows (1024-event cap)."""
    now = int(time.time()*1000); out = {}
    for w in range(0, days, 25):
        to = now - w*86400000; frm = to - 25*86400000
        d = get(f"{API}/v1/market-data/{mid}/funding/{frm}-{to}")
        if not d: continue
        for e in d.get("d", []): out[e["feb"]] = e
    return [out[k] for k in sorted(out)]

print(f"{'mkt':<6}{'events':>7}{'days':>6}{'atClamp%':>10}{'|max|':>7}{'mean':>8}"
      f"{'meanAPR%':>10}{'zero%':>7}{'flips':>7}")
print("-"*68)
rows = {}
for mid, name in MARKETS.items():
    ev = history(mid)
    if not ev:
        print(f"{name:<6}{'no data':>7}"); continue
    rates = [e["rate"] for e in ev]
    ppl   = [e["ppl"]  for e in ev]
    mx    = max(abs(r) for r in rates)
    clamp = sum(1 for r in rates if abs(r) == mx) / len(rates) * 100
    zero  = sum(1 for r in rates if r == 0) / len(rates) * 100
    flips = sum(1 for a, b in zip(rates, rates[1:]) if a*b < 0)
    ipy   = 365*86400/2580                      # intervals per year
    apr   = st.mean(rates)/1e6*ipy*100
    span  = (ev[-1]["at"]["t"]-ev[0]["at"]["t"])/86400000
    rows[name] = dict(ev=ev, rates=rates, ppl=ppl, mx=mx, clamp=clamp, apr=apr)
    print(f"{name:<6}{len(ev):>7}{span:>6.0f}{clamp:>10.1f}{mx:>7}{st.mean(rates):>8.1f}"
          f"{apr:>10.2f}{zero:>7.1f}{flips:>7}")

print("\nFIXED-LEG PRICING ERROR  (EMA-72 forecast vs realised, $/lot over the tenor)")
print(f"{'mkt':<6}{'tenor':>7}{'realised':>10}{'quoted':>9}{'MAE':>9}{'MAE/real':>10}")
print("-"*54)
def ema(xs, n):
    k = 2/(n+1); e = xs[0]
    for x in xs[1:]: e = x*k + e*(1-k)
    return e
for name, r in rows.items():
    p = r["ppl"]
    for tenor, label in ((33,"24h"), (98,"72h"), (234,"7d")):
        if len(p) < 72+tenor+10: continue
        errs, reals, quotes = [], [], []
        for i in range(72, len(p)-tenor, max(1, tenor//4)):
            q = ema(p[i-72:i], 72)*tenor      # fixed leg from trailing EMA
            a = sum(p[i:i+tenor])             # realised floating leg
            errs.append(abs(a-q)); reals.append(a); quotes.append(q)
        if not errs: continue
        mr = st.mean([abs(x) for x in reals]) or 1
        print(f"{name:<6}{label:>7}{st.mean(reals):>10.1f}{st.mean(quotes):>9.1f}"
              f"{st.mean(errs):>9.1f}{st.mean(errs)/mr:>9.0%}")
PREMIA_EOF

echo "==> files written:"
find . -type f -not -path './.git/*' -not -path './lib/*' | sort

# ---------------------------------------------------------------- foundry
if ! command -v forge >/dev/null 2>&1 || ! forge --version 2>/dev/null | grep -qi forge; then
  echo ""
  echo "!! Foundry's 'forge' is not on your PATH (another binary may be shadowing it)."
  echo "   Install it with:"
  echo "     curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup"
  echo "   Then re-run:  forge install foundry-rs/forge-std && forge test -vv"
  exit 0
fi

echo "==> installing forge-std"
forge install foundry-rs/forge-std

echo "==> running the fork test against Monad mainnet"
forge test --match-contract FundingReaderForkTest -vv
