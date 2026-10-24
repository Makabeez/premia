# Series 2 settled: the hedge delivered exactly the locked rate again (25 Oct 2026)

Series 2 was hedged from the phone on 8 Oct (see [series-2-mobile-hedge.md](series-2-mobile-hedge.md)):
a 0.01 ZEC long on Perpl plus a pay-fixed swap at K = −120 per lot per interval.

## Settlement

| Step | Tx | Block | Result |
|---|---|---|---|
| settle(2), deployer | [0xfcf61caf…8b79](https://monadvision.com/tx/0xfcf61caf5e60c21dd297d726a4fbefa6fd504348e6bfaa0caceac085c0f98b79) | 116305702 | `Settled(2, −4919, 33)` |
| claim(2), deployer (receive-fixed, 1 lot) | [0xafcc677d…44e0](https://monadvision.com/tx/0xafcc677db3ea96779c06b8fbfe2def11480014fdf47fe63853b1f99c8b5a44e0) | 116305722 | 0.040959 AUSD |
| claim(2), passkey wallet (pay-fixed, 1 lot), from the phone | [0xc45cdcde…8422](https://monadvision.com/tx/0xc45cdcde6e89dc3e30d92f0ea5042d962a8545bea358a8f3c86dcdc5a4e88422) | 116306940 | 0.039041 AUSD |
| close 0.01 ZEC long, from the phone | [0x1502222c…6569](https://monadvision.com/tx/0x1502222c6b973288797c1f05aa942f469db4e172a58efda825772981d1ce6569) | 116306973 | reduce-only IoC, filled at 1204.24 |
| withdraw collateral, from the phone | [0xf5eefff2…f296](https://monadvision.com/tx/0xf5eefff2b0f4781348588bd20ba06af30682da640d905a0715720fb6cb69f296) | 116306974 | 10.726574 AUSD to the wallet |

All five `status = 1`. Settled about 12 days after `endBlock` (112703479): the same answer a punctual settle
would have given, because both reads come from Perpl's historical funding accumulator.

## The math

Floating leg, read by `settle()` from Perpl:

```
getFundingSumAtBlock(50, 112420636) → 91356
getFundingSumAtBlock(50, 112703479) → 86437
difference                          → −4919 over 33 intervals (≈ −149 each; longs were paid)
```

Fixed leg: −120 × 33 = −3960.

| Leg | Per lot (funding units, 1 unit = 0.000001 AUSD) |
|---|---|
| Funding the 0.01 ZEC long received from Perpl | +4919 |
| PREMIA pay-fixed net: −4919 − (−3960) | −959 |
| **Total funding income for the hedged long** | **+3960 = 120 × 33, exactly the locked rate** |

Payouts: pay-fixed = cap + net = 40000 − 959 = 39041; receive-fixed = cap − net = 40000 + 959 = 40959.
Together they drain the 2 × 40000 escrow for this lot exactly.

## What this series shows

In series 1 funding fell well below the locked rate, and the hedge paid the long the difference.
In series 2 funding came in above the locked rate (≈ 149 vs 120 per interval), so the long gave up the
surplus. Both times the hedged long's funding income was exactly the fixed rate it locked. That is the
product: a known funding number, in either direction.

## Wallet after

Passkey wallet 0xD410065655dd3107e164e486AD80A8A138D34Dc5: 24.96 AUSD, Perpl account 0.00 AUSD, no open perp.
Price PnL on the perp (bought 1236.84, sold 1204.24) was −0.326 AUSD. PREMIA hedges funding, not price.

## Disclosure

The maker on the other side is the builder's deployer wallet. 2 unfilled maker lots (0.08 AUSD) remain in
escrow for series 2: the known stranded-escrow flaw documented in the README.
