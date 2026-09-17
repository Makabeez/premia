#!/usr/bin/env python3
"""PREMIA backtest: is Perpl funding worth hedging?
Pulls full funding history per market from the public Perpl API and answers:
  1. what fraction of intervals sit at the clamp (rate suppressed, not quiet)
  2. what a fixed leg would have cost vs realised, per tenor
No auth, no wallet. Run: python3 backtest.py
"""
import json, urllib.request, time, statistics as st

API = "https://app.perpl.xyz/api"
MARKETS = {1:"BTC",10:"MON",20:"ETH",31:"SOL",40:"HYPE",50:"ZEC",60:"LIT",90:"PUMP"}
DAYS = 90

HDRS = {"User-Agent": "premia-backtest/0.1", "Accept": "application/json"}

def get(url):
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers=HDRS)
            return json.load(urllib.request.urlopen(req, timeout=30))
        except Exception as e:
            if i == 2: print("  !", url[-40:], e)
            time.sleep(1.5*(i+1))
    return None

def history(mid, days=DAYS):
    """Walk backwards in <=25d windows (1024-event cap)."""
    now = int(time.time()*1000); out = {}
    for w in range(0, days, 25):
        to = now - w*86400000; frm = to - 25*86400000
        d = get(f"{API}/v1/market-data/{mid}/funding/{frm}-{to}")
        if not d: continue
        for e in d.get("d", []): out[e["feb"]] = e
    return [out[k] for k in sorted(out)]

print(f"{'mkt':<6}{'events':>7}{'days':>6}{'atClamp%':>10}{'|max|':>7}{'mean':>8}"
      f"{'meanAPR%':>10}{'zero%':>7}{'flips':>7}")
print("-"*68)
rows = {}
for mid, name in MARKETS.items():
    ev = history(mid)
    if not ev:
        print(f"{name:<6}{'no data':>7}"); continue
    rates = [e["rate"] for e in ev]
    ppl   = [e["ppl"]  for e in ev]
    mx    = max(abs(r) for r in rates)
    clamp = sum(1 for r in rates if abs(r) == mx) / len(rates) * 100
    zero  = sum(1 for r in rates if r == 0) / len(rates) * 100
    flips = sum(1 for a, b in zip(rates, rates[1:]) if a*b < 0)
    ipy   = 365*86400/2580                      # intervals per year
    apr   = st.mean(rates)/1e6*ipy*100
    span  = (ev[-1]["at"]["t"]-ev[0]["at"]["t"])/86400000
    rows[name] = dict(ev=ev, rates=rates, ppl=ppl, mx=mx, clamp=clamp, apr=apr)
    print(f"{name:<6}{len(ev):>7}{span:>6.0f}{clamp:>10.1f}{mx:>7}{st.mean(rates):>8.1f}"
          f"{apr:>10.2f}{zero:>7.1f}{flips:>7}")

print("\nFIXED-LEG PRICING ERROR  (EMA-72 forecast vs realised, $/lot over the tenor)")
print(f"{'mkt':<6}{'tenor':>7}{'realised':>10}{'quoted':>9}{'MAE':>9}{'MAE/real':>10}")
print("-"*54)
def ema(xs, n):
    k = 2/(n+1); e = xs[0]
    for x in xs[1:]: e = x*k + e*(1-k)
    return e
for name, r in rows.items():
    p = r["ppl"]
    for tenor, label in ((33,"24h"), (98,"72h"), (234,"7d")):
        if len(p) < 72+tenor+10: continue
        errs, reals, quotes = [], [], []
        for i in range(72, len(p)-tenor, max(1, tenor//4)):
            q = ema(p[i-72:i], 72)*tenor      # fixed leg from trailing EMA
            a = sum(p[i:i+tenor])             # realised floating leg
            errs.append(abs(a-q)); reals.append(a); quotes.append(q)
        if not errs: continue
        mr = st.mean([abs(x) for x in reals]) or 1
        print(f"{name:<6}{label:>7}{st.mean(reals):>10.1f}{st.mean(quotes):>9.1f}"
              f"{st.mean(errs):>9.1f}{st.mean(errs)/mr:>9.0%}")
