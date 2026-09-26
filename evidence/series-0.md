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

## Settlement (26 Sept 2026)

Settled 1,426,004 blocks (~119 h) after `endBlock`, by design: the funding
sum is read historically, so a late `settle()` returns the same answer as
a punctual one.

| step   | tx |
|--------|----|
| settle | [0x86d82d86…711c](https://app.blocksec.com/phalcon/explorer/tx/monad/0x86d82d8615146f20e76af4ae84a7fbf28245654ac62232b8efb98699b803711c) — block 108287067 |
| claim  | [0xddaacf8f…98fd](https://app.blocksec.com/phalcon/explorer/tx/monad/0xddaacf8fb90c0a0f2e8a57e18f1f10cd6b8c0b4d589641d7b980a4163db798fd) — block 108287211 |

**Settled(0, netPerLot = -1694, intervals = 33)**

- Fsum[ZEC] @106571814 = 235338, @106854657 = 233644 → floating leg −1694 per lot
- 33 intervals counted from Perpl's recorded funding-event blocks, matching the 33 listed
- Fixed leg: K = 68 × 33 = 2244 → net −3938 per lot (16% of the ±25000 cap)
- Per lot: PayFixed 21062, ReceiveFixed 28938 (sum 50000 = 2 × cap)
- 10 lots → PayFixed 0.210620 AUSD, ReceiveFixed 0.289380 AUSD
- **ReceiveFixed wins**: realised ZEC funding came in below the 68/interval fixed rate

Claim paid 500000 raw units (0.500000 AUSD) to the single wallet holding both
sides. Contract AUSD balance after claim: **0**. The pot drained exactly.

Anyone can reproduce the settlement number with two view calls, no archive node needed:

    cast call 0x34B6552d57a35a1D042CcAe1951BD1C370112a6F \
      "getFundingSumAtBlock(uint256,uint256)(int256,uint256)" 50 106578220 --rpc-url https://rpc.monad.xyz
    cast call 0x34B6552d57a35a1D042CcAe1951BD1C370112a6F \
      "getFundingSumAtBlock(uint256,uint256)(int256,uint256)" 50 106861063 --rpc-url https://rpc.monad.xyz
