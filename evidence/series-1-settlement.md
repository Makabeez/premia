# Series 1 settled: the hedge delivered exactly the locked rate (1 Oct 2026)

| step | tx | result |
|------|----|--------|
| settle(1) | 0xfe9a1bbf21db9e7a7c2eb478bc8789bdfa895007ce982c27c58ca3fdc44419d7 | Settled(1, -2440, 33), block 109724626 |
| claim(1), deployer (receive-fixed, 2 lots) | 0x61945688b5fcdd9f65c5b39117d6657bf1c99aa9a112ad484914b0b7df5ef4c9 | 0.062704 AUSD |
| claim(1), passkey wallet (pay-fixed, 2 lots), from the phone | 0xc5686857c72e015c69ae47f10e1675b4f9089a57f2e823e361e6f7b1fedc8208 | 0.097296 AUSD |
| close the 0.01 ZEC long on Perpl, from the phone | 0x429787d41c4ae014b4d07747d098ca436b706024f580134bd8707026772758be | position 0 |
| withdrawCollateral, from the phone | 0x958f11acfea7cee83aa0b8a975379ca2e25237fb9cf8e4c4c99ad5a32bc6bb4f | 10.214030 AUSD back to the wallet |

Settled ~24 h after `endBlock` (109431565): same answer as a punctual settle, by construction.

## The point of the product, in one series

Funding when the hedge was struck (K = -336/lot/interval, ~-29% APR, longs paid) collapsed to
**-74/lot/interval** over the window. A long that had relied on that income lost ~78% of it.
The long that locked it did not:

| per lot, over 33 intervals | AUSD units |
|---|---|
| funding received by the 0.01 ZEC long on Perpl (Fsum moved -2440) | +2440 |
| PREMIA pay-fixed net: floating -2440 minus fixed (-336 x 33 = -11088) | +8648 |
| **total funding income** | **+11088 = 336 x 33, exactly the locked rate** |

The perp was opened at block 109124353 (before the series started at 109148722) and closed at
109724964 (after it ended), so it was held across the whole window.

## Honest accounting

- The passkey wallet held **2 swap lots against 1 perp lot** (one swap-only test lot from 28 Sept),
  so it was over-hedged 2:1; the second lot also earned +8648 units.
- PREMIA hedges **funding, not price**. The perp account returned 10.214030 of the 11 AUSD
  deposited: ZEC's price move, trading fees and funding together, of which only funding was locked.
- Both counterparties are the builder's wallets.
- **Contract flaw found here:** the deployer's 3 unfilled resting lots (0.12 AUSD escrow) cannot be
  recovered. `cancelQuote` reverts after `startBlock` and `claim` pays fills only, so unfilled
  escrow has no exit once trading closes. Pot after both claims: exactly 0.12 AUSD, all of it from
  those unfilled quotes. Fix: refund live quotes in `claim`, or allow `cancelQuote` after start.
