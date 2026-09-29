# One tap: perp + hedge from a passkey wallet (29 Sept 2026)

Wallet 0xD410065655dd3107e164e486AD80A8A138D34Dc5 (passkey, Galaxy S25 Ultra). One button press,
four transactions in blocks 109124350-109124355, no seed phrase, no second prompt:

| tx | call | result |
|----|------|--------|
| 0xed463dd65f4f11a6834fd31b1e984be21620382f0a788047685a2e09007a1756 | AUSD.approve(Perpl) | ok |
| 0x3e6d96e1c6ac26cf892b4cbfd1a1c5f7940a391b6f9b207f80246e50e9bdc8a1 | Perpl.createAccount(11 AUSD) | account 5365 |
| 0x543165d15ac738939f1dcaacab6a00f3e39b5725dee1eb947a339408244efe81 | Perpl.execOrder(OpenLong, IoC) | long 0.01 ZEC @ 1400.35, 2x |
| 0xf741cefc9bb776669dec14e6f19e429b29a3e694ca0f71ba6014e8f4713a5d34 | PremiaSwap.take(series 1, PayFixed, 1) | K = -336 |

1 PREMIA lot = 0.01 ZEC = 100 Perpl lot units, so the hedge ratio is 1:1 by construction.
A long pays floating funding; pay-fixed receives floating and pays K, so the long's net funding is -K.

Disclosure: the maker is the builder's deployer wallet. The passkey wallet also holds one
swap-only lot from 28 Sept (series-1.md), so it is 2 swap lots vs 1 perp lot.
