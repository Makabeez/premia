# Series 2 · one-tap hedge from the phone · 8 Oct 2026

Recorded on video: https://youtube.com/shorts/nr0ALj4d1-o

One tap on **Lock my ZEC funding · 1 lot** in the PREMIA Android app, signed with one passkey prompt.
The Perpl account had been emptied by the series-1 withdraw, so the app topped it up first.

| Step | Tx | Block | What it did |
|---|---|---|---|
| approve | [0xec568f33…549b](https://monadvision.com/tx/0xec568f331dc3b04933fbd91982fd6a42f65e99a3b43ee9bec1485a60e675549b) | 111565158 | AUSD allowance 11.000000 to Perpl Exchange |
| depositCollateral | [0x09ed67d7…f48d](https://monadvision.com/tx/0x09ed67d7ee0e99499aa0b8cef14cd551f35f828aca4ca049388891652026f48d) | 111565160 | 11.000000 AUSD into Perpl account 5365 |
| execOrder | [0x5b845d74…daa2](https://monadvision.com/tx/0x5b845d74bd0eeb347d80d21bf5f318c232e04db5d4cb2f6ea984b68a9ad1daa2) | 111565162 | long 0.01 ZEC @ 1236.84, 2x |
| take | [0x0b622301…14dd](https://monadvision.com/tx/0x0b622301b0dbab7648809014584efa1279d0e686727f290291e3281fa38814dd) | 111565164 | pay-fixed 1 lot, series 2, tick 108 (K = −120), 0.04 AUSD escrowed |

All four `status = 1`. Blocks 111565158 → 111565164, timestamps 1791448946 → 1791448948 (about 2 s).

## Series 2

| | |
|---|---|
| createSeries | [0x7d4094c4…3378](https://monadvision.com/tx/0x7d4094c4a2bde78f8893a7700195fb20591cbca2bae6027103bae00376f63378), block 111560644 |
| Window | blocks 112420636 → 112703479, 33 funding intervals |
| Maker quote | [0x87423a9a…19bf](https://monadvision.com/tx/0x87423a9af2f247f2ee573b0b082172c309a1a37356e22fbd1654f89eb4b619bf): receive-fixed, tick 108 (K = −120), 3 lots, 0.12 AUSD escrow |
| Fill | `Filled(series 2, taker 0xD410…4Dc5, maker 0x1BcE…2d19, side 0, tick 108, 1 lot)` |

The hedge limit came from the live `bestTick(2, 1)`, not a hardcoded tick.

## Wallet before → after (from the app's balance card)

| | Before | After |
|---|---|---|
| Wallet AUSD | 25.23 | 14.19 (−11.00 deposit, −0.04 swap escrow) |
| Perpl free collateral | 0.00 | 4.80 |
| Position | none | long 0.01 ZEC @ 1236.84 |

## Disclosure

The maker is the builder's deployer wallet. Settlement is pending until block 112703479 (about Sun 12 Oct 2026).
