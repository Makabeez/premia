# Series 1: first hedge signed by a passkey wallet (28 Sept 2026)

ZEC (market 50), 33 intervals, blocks 109148722 -> 109431565.
Grid widened vs series 0 (minK -768, tickStep 6, cap 40000): trailing ZEC funding
was ~-350/lot/interval, at the floor of series 0's grid.

| step | tx |
|------|----|
| createSeries | 0xd654ecf99c7620075740069c98cf5a0312bbe17215b9b2a37fd2c2208d50aa5f |
| maker quote: receive-fixed, 5 lots, tick 72 (K=-336), deployer 0x1BcE...2d19 | 0xc4b6706e4e0a55068c0c3bec6a951639902f4efa8de2271b7c58f1062c033826 |
| **taker: pay-fixed 1 lot, signed by passkey wallet 0xD410...4Dc5 from a phone** | 0x244572a6be0603672b3fc1b8b674566c20dc667842cb9e481cd8bd9af0315ceb |

fillsOf(1, passkey)  = [(1 lot, K -336, PayFixed)]
fillsOf(1, deployer) = [(1 lot, K -336, ReceiveFixed)]

Disclosure: both addresses belong to the builder. The taker is a separate passkey-derived
EOA on a Galaxy S25 Ultra; no private key exists on disk for it.
