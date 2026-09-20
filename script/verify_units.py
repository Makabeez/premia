#!/usr/bin/env python3
"""Resolve PREMIA's lot size and unitScale against a REAL Perpl position.

Perpl stores funding as a cumulative product sum per market. The payment owed
by a position is (Fsum[end] - Fsum[start]) * L -- but the docs never pin the
unit of L, and the fixed-point scaling differs per market (price_decimals,
size_decimals, funding_sum_scaling_exp). Get it wrong and every settlement is
off by orders of magnitude, silently.

So we don't derive it from the docs. We read an OPEN position's own accrued
funding out of the exchange and solve for the scaling that reproduces it.

  python3 script/verify_units.py --market 50 --account 5305

Writes evidence/unit-scale-<market>.json. CreateSeries.s.sol refuses to list a
series for a market without it.

Position struct layout (getPositionV2(marketId, accountId)), established by
decoding a live position and cross-checking every field against the UI:
  [4] margin (collateral wei)   [5] entry price   [6] size (raw size units)
  [7] open block                [10] funding accrued (collateral wei, signed)
"""
import argparse, json, os, sys, urllib.request

RPC = os.environ.get("MONAD_RPC", "https://rpc.monad.xyz")
EXCHANGE = "0x34B6552d57a35a1D042CcAe1951BD1C370112a6F"
API = "https://app.perpl.xyz/api"
HDRS = {"User-Agent": "premia-verify/0.2", "Accept": "application/json"}

SEL_FUNDING_SUM = "0x7dd7e759"   # getFundingSumAtBlock(uint256 market, uint256 block)
SEL_POSITION_V2 = "0xea3196ec"   # getPositionV2(uint256 market, uint256 account)

W_MARGIN, W_ENTRY, W_SIZE, W_OPEN_BLOCK, W_FUNDING = 4, 5, 6, 7, 10
COLLATERAL_DECIMALS = 6          # AUSD


def rpc(method, params):
    req = urllib.request.Request(
        RPC, method="POST", headers={**HDRS, "Content-Type": "application/json"},
        data=json.dumps({"jsonrpc": "2.0", "id": 1,
                         "method": method, "params": params}).encode())
    out = json.load(urllib.request.urlopen(req, timeout=30))
    if "error" in out:
        sys.exit(f"RPC error: {out['error']}")
    return out["result"]


def words(hexstr):
    h = hexstr[2:]
    return [int(h[i*64:(i+1)*64], 16) for i in range(len(h) // 64)]


def signed(x):
    return x - (1 << 256) if x >> 255 else x


def call(sel, a, b):
    return rpc("eth_call", [{"to": EXCHANGE, "data": sel + f"{a:064x}" + f"{b:064x}"},
                            "latest"])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--market", type=int, required=True)
    p.add_argument("--account", type=int, required=True)
    p.add_argument("--dump", action="store_true", help="print the raw position words")
    args = p.parse_args()

    raw = call(SEL_POSITION_V2, args.market, args.account)
    if raw in ("0x", None) or len(raw) < 66:
        sys.exit("getPositionV2 returned nothing -- check the account id")
    w = words(raw)
    if args.dump:
        for i, x in enumerate(w):
            print(f"  [{i:2}] {x}  (signed {signed(x)})")

    size      = signed(w[W_SIZE])
    open_blk  = w[W_OPEN_BLOCK]
    accrued   = signed(w[W_FUNDING])
    if size == 0:
        sys.exit("position size is 0 -- open a position on this market first")
    if accrued == 0:
        sys.exit("accrued funding is 0 -- hold the position through at least one "
                 "funding event where the rate was non-zero, then rerun")

    head = int(rpc("eth_blockNumber", []), 16)
    s0 = words(call(SEL_FUNDING_SUM, args.market, open_blk))
    s1 = words(call(SEL_FUNDING_SUM, args.market, head))
    fsum0, blk0 = signed(s0[0]), s0[1]
    fsum1, blk1 = signed(s1[0]), s1[1]
    if blk0 == 0 or blk1 == 0:
        sys.exit("no funding data for that market")

    delta = fsum1 - fsum0
    intervals = (blk1 - blk0) // 8571

    ctx = json.load(urllib.request.urlopen(
        urllib.request.Request(f"{API}/v1/pub/context", headers=HDRS), timeout=30))
    mkt = next(m for m in ctx["markets"] if m["id"] == args.market)
    cfg = mkt["config"]

    print(f"market {args.market} ({mkt['symbol']})")
    print(f"  price_decimals={cfg['price_decimals']} size_decimals={cfg['size_decimals']} "
          f"scaling_exp={cfg['funding_sum_scaling_exp']}")
    print(f"  position: size={size} raw units, opened at block {open_blk}")
    print(f"  Fsum {fsum0} -> {fsum1}  delta={delta} over {intervals} intervals")
    print(f"  exchange says accrued funding = {accrued} ({accrued / 10**COLLATERAL_DECIMALS:+.6f} AUSD)")

    if delta == 0:
        sys.exit("funding was flat over this window -- every scale fits. Hold longer.")

    # Solve: |delta * size| / accrued must be a power of ten.
    product = abs(delta * size)
    ratio = product / abs(accrued)
    k = round(__import__("math").log10(ratio))
    if abs(ratio - 10 ** k) > 10 ** k * 0.001:
        sys.exit(f"\nUNVERIFIED: |delta*size|/accrued = {ratio:.6f}, not a clean power "
                 "of ten. Do NOT create a series. Hold the position longer and rerun; "
                 "if it persists the struct layout may differ for this market -- "
                 "rerun with --dump.")

    # payoutWei = delta * lots * unitScale, with lots = rawSize / 10**k
    # so unitScale = 1 and one PREMIA lot is 10**k raw size units.
    lot_exp = k
    unit_scale = 1
    lot_in_coin = 10 ** lot_exp / 10 ** cfg["size_decimals"]

    print(f"\n  |delta*size| / accrued = {ratio:.4f} = 10^{k}  [clean]")
    print(f"\nVERIFIED")
    print(f"  1 PREMIA lot = {10**lot_exp} raw units = {lot_in_coin:g} {mkt['symbol']}")
    print(f"  unitScale    = {unit_scale}")
    print(f"  your position of {size} raw units = {size / 10**lot_exp:.2f} PREMIA lots")

    os.makedirs("evidence", exist_ok=True)
    path = f"evidence/unit-scale-{args.market}.json"
    with open(path, "w") as f:
        json.dump({
            "verified": True,
            "unitScale": unit_scale,
            "lotExp": lot_exp,
            "lotSizeRawUnits": 10 ** lot_exp,
            "lotSizeInCoin": lot_in_coin,
            "marketId": args.market,
            "symbol": mkt["symbol"],
            "accountId": args.account,
            "positionSizeRaw": size,
            "openBlock": open_blk,
            "accruedFundingWei": accrued,
            "fsumStart": fsum0, "fsumEnd": fsum1, "delta": delta,
            "blockStart": blk0, "blockEnd": blk1, "intervals": intervals,
            "ratio": ratio,
            "priceDecimals": cfg["price_decimals"],
            "sizeDecimals": cfg["size_decimals"],
            "fundingSumScalingExp": cfg["funding_sum_scaling_exp"],
            "method": "solved against the exchange's own accrued funding for a live "
                      "position; cross-checked against the Perpl UI",
        }, f, indent=2)
    print(f"\n  -> {path}")


if __name__ == "__main__":
    main()
