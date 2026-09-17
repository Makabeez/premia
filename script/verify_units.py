#!/usr/bin/env python3
"""Resolve PREMIA's unitScale against a REAL Perpl position.

The one number the contract cannot derive for itself is how many AUSD wei a
single funding unit is worth. Perpl stores funding as a cumulative product sum
per market, scaled by `funding_sum_scaling_exp` and by that market's price
decimals -- and the docs define the payment as (Fsum[j] - Fsum[m]) * L without
pinning the unit of L. Getting it wrong is silent and costs orders of magnitude.

So we don't derive it. We open a position on Perpl, let it sit through a few
funding events, then ask the exchange what IT thinks that position owes and
find the scale that reproduces the number.

  python3 script/verify_units.py --market 50 --account <id> --lots <size> \
      --start-block <block when position opened>

Writes evidence/unit-scale-<market>.json on success. CreateSeries.s.sol will
not create a series for a market without it.
"""
import argparse, json, os, sys, urllib.request

RPC = os.environ.get("MONAD_RPC", "https://rpc.monad.xyz")
EXCHANGE = "0x34B6552d57a35a1D042CcAe1951BD1C370112a6F"
API = "https://app.perpl.xyz/api"
HDRS = {"User-Agent": "premia-verify/0.1", "Accept": "application/json"}

SEL_FUNDING_SUM = "0x7dd7e759"   # getFundingSumAtBlock(uint256,uint256)
SEL_POSITION_V2 = "0xea3196ec"   # getPositionV2(uint256,uint256)

CANDIDATES = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000,
              10_000_000, 100_000_000, 1_000_000_000]


def rpc(method, params):
    req = urllib.request.Request(
        RPC, method="POST", headers={**HDRS, "Content-Type": "application/json"},
        data=json.dumps({"jsonrpc": "2.0", "id": 1,
                         "method": method, "params": params}).encode())
    out = json.load(urllib.request.urlopen(req, timeout=30))
    if "error" in out:
        sys.exit(f"RPC error: {out['error']}")
    return out["result"]


def word(hexstr, i):
    raw = int(hexstr[2 + i * 64: 66 + i * 64], 16)
    return raw - (1 << 256) if raw >> 255 else raw


def call(sel, a, b):
    data = sel + f"{a:064x}" + f"{b:064x}"
    return rpc("eth_call", [{"to": EXCHANGE, "data": data}, "latest"])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--market", type=int, required=True)
    p.add_argument("--account", type=int, required=True)
    p.add_argument("--lots", type=float, required=True,
                   help="position size as YOU entered it on Perpl (e.g. 0.05)")
    p.add_argument("--start-block", type=int, required=True)
    p.add_argument("--tolerance", type=float, default=0.02)
    args = p.parse_args()

    head = int(rpc("eth_blockNumber", []), 16)

    s0 = call(SEL_FUNDING_SUM, args.market, args.start_block)
    s1 = call(SEL_FUNDING_SUM, args.market, head)
    fsum0, blk0 = word(s0, 0), word(s0, 1)
    fsum1, blk1 = word(s1, 0), word(s1, 1)
    if blk0 == 0 or blk1 == 0:
        sys.exit("no funding data for that market/window")

    delta = fsum1 - fsum0
    intervals = (blk1 - blk0) // 8571
    print(f"market {args.market}: fsum {fsum0} -> {fsum1}  delta={delta} "
          f"over {intervals} intervals (blocks {blk0} -> {blk1})")
    if intervals < 2:
        sys.exit("hold the position through at least 2 funding events first")
    if delta == 0:
        sys.exit("funding was exactly flat over this window -- useless as a "
                 "calibration; wait for a window where the rate moved")

    # market config, for the record
    ctx = json.load(urllib.request.urlopen(
        urllib.request.Request(f"{API}/v1/pub/context", headers=HDRS), timeout=30))
    mkt = next(m for m in ctx["markets"] if m["id"] == args.market)
    cfg = mkt["config"]
    print(f"           symbol={mkt['symbol']} price_decimals={cfg['price_decimals']} "
          f"size_decimals={cfg['size_decimals']} scaling_exp={cfg['funding_sum_scaling_exp']}")

    pos = call(SEL_POSITION_V2, args.account, args.market)
    if pos in ("0x", None) or len(pos) < 66:
        sys.exit("getPositionV2 returned nothing -- wrong account id, or no "
                 "open position on this market")

    nwords = (len(pos) - 2) // 64
    print(f"\ngetPositionV2 returned {nwords} words; searching for premium PNL")

    hits = []
    for i in range(nwords):
        w = word(pos, i)
        if w == 0:
            continue
        for scale in CANDIDATES:
            for lot_basis, label in ((1, "whole units"),
                                     (10 ** cfg["size_decimals"], "raw size units")):
                expected = delta * args.lots * lot_basis * scale
                if expected == 0:
                    continue
                if abs(w - expected) <= abs(expected) * args.tolerance:
                    hits.append((i, w, scale, label, expected))

    if not hits:
        print("\nNo word matched. Raw words, for manual inspection:")
        for i in range(nwords):
            print(f"  [{i:2}] {word(pos, i)}")
        sys.exit("\nUNVERIFIED -- do not create a series. Widen --tolerance, or "
                 "check the account id and that the position was open for the "
                 "whole window.")

    print("\nMatches:")
    for i, w, scale, label, exp in hits:
        print(f"  word[{i}] = {w}  ~  delta*lots*{scale} ({label}, expected {exp:.0f})")

    scales = {h[2] for h in hits}
    if len(scales) > 1:
        sys.exit(f"\nAMBIGUOUS -- {sorted(scales)} all fit within tolerance. "
                 "Hold the position longer so the numbers separate, then rerun.")

    scale = scales.pop()
    os.makedirs("evidence", exist_ok=True)
    path = f"evidence/unit-scale-{args.market}.json"
    with open(path, "w") as f:
        json.dump({
            "verified": True,
            "unitScale": scale,
            "marketId": args.market,
            "symbol": mkt["symbol"],
            "accountId": args.account,
            "lots": args.lots,
            "fsumStart": fsum0, "fsumEnd": fsum1, "delta": delta,
            "blockStart": blk0, "blockEnd": blk1, "intervals": intervals,
            "priceDecimals": cfg["price_decimals"],
            "sizeDecimals": cfg["size_decimals"],
            "fundingSumScalingExp": cfg["funding_sum_scaling_exp"],
            "matchedWords": [h[0] for h in hits],
        }, f, indent=2)
    print(f"\nVERIFIED. unitScale = {scale}  ->  {path}")
    print("CreateSeries.s.sol will now accept this market.")


if __name__ == "__main__":
    main()
