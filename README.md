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
| **PremiaSwap** | **`0x4695e7747555857929CA99FC86A9F44cef832749`** (verified on Sourcify) ([deploy tx](https://monadscan.com/tx/0x5c2da79f4bfd1af8cff762345e0382638b0c9e8747bc5c07aa2470a29374aec5)) |
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
- [x] Swap contract + on-chain quote book — **live on Monad mainnet**
- [ ] Mobile client (React Native + Mera passkey accounts + AUSD)
- [ ] Maker bot

## Licence

MIT
