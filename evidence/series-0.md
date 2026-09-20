# Series 0 — ZEC 24h, Monad mainnet

Contract `0x4695e7747555857929CA99FC86A9F44cef832749`

| step | tx |
|---|---|
| deploy | [0x5c2da79f](https://monadscan.com/tx/0x5c2da79f4bfd1af8cff762345e0382638b0c9e8747bc5c07aa2470a29374aec5) |
| createSeries | [0xfb979358](https://monadscan.com/tx/0xfb9793589424ff0aa1deb22d0a083d823f3ab88618690e9c3968f3a14648ee32) |
| postQuote | [0x9e9456fd](https://monadscan.com/tx/0x9e9456fda15902d7d82622f8f7ef8ed7a96aea27decad1a6d4845323f0932415) |
| take | [0x227b0c3f](https://monadscan.com/tx/0x227b0c3fe4f9621044ce283dc20244341bcebaa8105ab14fe9dbaba1c280d51e) |

Params: market 50 (ZEC), start 106578220, end 106861063, 33 intervals,
cap 25000, minK -400, tickStep 4, unitScale 1 (verified, evidence/unit-scale-50.json).

Filled 10 lots (0.10 ZEC notional) at tick 117 = K 68 wei/lot/interval, the
measured median. Escrow 250,000 wei ($0.25) per side.

REAL / SIMULATED: everything above is real mainnet. Both sides of this fill came
from the same wallet — it validates the mechanism, it is not traction. Recorded
fills for the submission use distinct counterparties.
