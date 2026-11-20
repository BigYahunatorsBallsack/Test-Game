#!/usr/bin/env python3
"""Paket 4.6: Direktkauf-Preise aus den Kisten-Daten (exakt, mit Gold-Pity).

Aufruf: python3 docs/balance/directshop_4_6.py   (nur Standardbibliothek, kein Zufall)

Liest src/shared/Data/Crates.luau, CrateItems.luau und Economy.luau. Ändert nichts.

Regel (Vorschlag):
  1. Für jede Gem-Kiste ohne eventOnly, die das Item enthält:
       EV(Item, Kiste) = Kistenpreis / P(genau dieses Item je Öffnung)
       P = Rate der Seltenheit je Öffnung / Poolgröße (Kiste, Seltenheit).
       Rate ohne Pity = Quote / 10000. Rate mit Pity = Langzeitrate je Öffnung
       aus der exakten Markov-Kette über (sinceEpic, sinceLegendary).
  2. EV(Item) = kleinster Wert über diese Kisten.
  3. Aufrunden auf 2 signifikante Stellen.
  4. Optional: monotone Untergrenze. Je Seltenheit in Rang-Reihenfolge: Preis mindestens
     der Einstiegspreis (billigstes Item) jeder niedrigeren Seltenheit. Hebt nur an.
"""
from __future__ import annotations

import math
import os
import re
from fractions import Fraction as F

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]  # Rang 1 bis 6
RANK = {r: i + 1 for i, r in enumerate(RARITIES)}
DE = {"common": "Gewöhnlich", "uncommon": "Ungewöhnlich", "rare": "Selten",
      "epic": "Episch", "legendary": "Legendär", "mythic": "Mythisch"}
ODDS_TOTAL = 10000


# ---------------------------------------------------------------- Daten lesen
def read(path: str) -> str:
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def load_crates():
    src = read("src/shared/Data/Crates.luau")
    odds_src = re.search(r"local Odds.*?=\s*\{(.*?)\n\}", src, re.S).group(1)
    odds = {}
    for name, block in re.findall(r"(\w+)\s*=\s*\{(.*?)\}", odds_src, re.S):
        odds[name] = {r: int(re.search(r"\b" + r + r"\s*=\s*(\d+)", block).group(1)) for r in RARITIES}
    list_src = re.search(r"local list: \{ Crate \} = \{(.*?)\n\}", src, re.S).group(1)
    crates = {}
    for block in re.findall(r"\n    \{(.*?)\n    \},", list_src, re.S):
        cid = re.search(r'id = "(\w+)"', block).group(1)
        pity_m = re.search(r"pity = \{ epic = (\d+), legendary = (\d+) \}", block)
        crates[cid] = {
            "currency": re.search(r'currency = "(\w+)"', block).group(1),
            "price": int(re.search(r"price = (\d+)", block).group(1)),
            "odds": odds[re.search(r"odds = Odds\.(\w+)", block).group(1)],
            "pity": (int(pity_m.group(1)), int(pity_m.group(2))) if pity_m else None,
            "eventOnly": re.search(r"eventOnly = (\w+)", block).group(1) == "true",
        }
    return crates


def load_items():
    src = read("src/shared/Data/CrateItems.luau")
    pat = re.compile(r'\{ id = "([^"]+)", kind = "[^"]+", name = "([^"]*)", rarity = "([^"]+)", '
                     r'crates = \{([^}]*)\}, effectBp = (\d+) \}')
    return [{"id": m.group(1), "name": m.group(2), "rarity": m.group(3),
             "crates": re.findall(r'"([^"]+)"', m.group(4)), "effectBp": int(m.group(5))}
            for m in pat.finditer(src)]


def load_max_gems() -> int:
    return int(re.search(r"maxGems = ([\d_]+)", read("src/shared/Data/Economy.luau")).group(1).replace("_", ""))


# ---------------------------------------------------------------- Pity-Kette (exakt)
def pity_rates(odds, pity_epic: int, pity_leg: int) -> dict[str, F]:
    """Langzeitrate je Öffnung und Seltenheit, Regeln wie Logic/CrateRoll.

    sinceLegendary >= pity_leg - 1: nur Legendär+. Sonst sinceEpic >= pity_epic - 1: nur Episch+.
    Legendär+ setzt beide Zähler auf 0, Episch nur sinceEpic, sonst beide +1.
    Jeder Legendär+-Treffer springt nach (0, 0): Erneuerungspunkt. Rate = Erwartung je Zyklus
    geteilt durch mittlere Zykluslänge (exakt, Fraction).
    """
    def table(min_rank: int):
        allowed = [r for r in RARITIES if RANK[r] >= min_rank and odds[r] > 0]
        tot = sum(odds[r] for r in allowed)
        return [(r, F(odds[r], tot)) for r in allowed]

    normal, epic_g, leg_g = table(1), table(RANK["epic"]), table(RANK["legendary"])
    mass = {(0, 0): F(1)}
    count = {r: F(0) for r in RARITIES}
    length = F(0)
    while mass:
        nxt: dict[tuple[int, int], F] = {}
        for (e, l), p in mass.items():
            length += p
            dist = leg_g if l >= pity_leg - 1 else epic_g if e >= pity_epic - 1 else normal
            for r, q in dist:
                count[r] += p * q
                if RANK[r] >= RANK["legendary"]:
                    continue  # Zyklus endet
                s = (0, l + 1) if r == "epic" else (e + 1, l + 1)
                nxt[s] = nxt.get(s, F(0)) + p * q
        mass = nxt
    return {r: count[r] / length for r in RARITIES}


def rates_of(crate) -> dict[str, F]:
    if crate["pity"]:
        return pity_rates(crate["odds"], *crate["pity"])
    return {r: F(crate["odds"][r], ODDS_TOTAL) for r in RARITIES}


# ---------------------------------------------------------------- Rundung
def ceil_sig(x: F, digits: int = 2) -> int:
    """Aufrunden auf `digits` signifikante Stellen, exakt (nie unter x)."""
    if x <= 0:
        return 0
    n = len(str(math.floor(x)))  # Stellen vor dem Komma (x >= 1 hier immer)
    step = 10 ** max(n - digits, 0)
    return math.ceil(x / step) * step


# ---------------------------------------------------------------- Rechnung
def main():
    crates = load_crates()
    items = load_items()
    max_gems = load_max_gems()
    gem_crates = {cid: c for cid, c in crates.items() if c["currency"] == "gems" and not c["eventOnly"]}
    rates = {cid: rates_of(c) for cid, c in gem_crates.items()}
    pools = {}
    for it in items:
        for cid in it["crates"]:
            pools.setdefault((cid, it["rarity"]), []).append(it["id"])

    # Gegenprobe zu crates_4_2.md (Gold mit Pity, auf 6 Stellen).
    ref = {"uncommon": 0.395588, "rare": 0.395588, "epic": 0.154955, "legendary": 0.048481, "mythic": 0.005387}
    for r, v in ref.items():
        assert abs(float(rates["gold"][r]) - v) < 5e-7, (r, float(rates["gold"][r]))
    assert sum(rates["gold"].values()) == 1

    print("== Langzeitrate je Öffnung, Goldkiste mit Pity", crates["gold"]["pity"], "==")
    for r in RARITIES:
        q = rates["gold"][r]
        print(f"  {DE[r]:13s} {float(q):.10f}  (Tabelle {crates['gold']['odds'][r] / ODDS_TOTAL:.4f})")
    print(f"  Episch+       {float(sum(rates['gold'][r] for r in RARITIES[3:])):.10f}")
    print(f"  Legendär+     {float(sum(rates['gold'][r] for r in RARITIES[4:])):.10f}")
    print(f"  Nenner der exakten Bruchzahlen: {len(str(rates['gold']['mythic'].denominator))} Stellen")

    rows = []
    for it in items:
        if all(crates[c]["eventOnly"] for c in it["crates"]):
            continue  # Event-Item: kein Direktpreis
        cands = []
        for cid in it["crates"]:
            if cid not in gem_crates:
                continue
            p_item = rates[cid][it["rarity"]] / len(pools[(cid, it["rarity"])])
            if p_item > 0:
                cands.append((gem_crates[cid]["price"] / p_item, cid, p_item))
        assert cands, it["id"]
        ev, cid, p_item = min(cands)
        rows.append({**it, "ev": ev, "crate": cid, "p": p_item, "all": cands, "r2": ceil_sig(ev, 2), "r3": ceil_sig(ev, 3)})

    # Monotone Untergrenze: Einstiegspreis (billigstes Item) jeder niedrigeren Seltenheit.
    floor = 0
    entry = {}
    for r in RARITIES:
        rr = [x for x in rows if x["rarity"] == r]
        for x in rr:
            x["mono"] = max(x["r2"], floor)
        if rr:
            entry[r] = min(x["mono"] for x in rr)
            floor = max(floor, entry[r])

    print("\n== Direktpreis je Item (Gems) ==")
    print(f"  {'Item':26s} {'Selt.':10s} {'Kiste':5s} {'P je Öffnung':>13s} {'EV exakt':>12s} "
          f"{'2 sig.':>8s} {'+%':>5s} {'monoton':>8s} {'3 sig.':>8s}  andere Kisten")
    for x in rows:
        others = ", ".join(f"{c} {float(v):,.1f}" for v, c, _ in x["all"] if c != x["crate"])
        print(f"  {x['id']:26s} {x['rarity']:10s} {x['crate']:5s} {float(x['p']):13.9f} {float(x['ev']):12.3f} "
              f"{x['r2']:8d} {float(x['r2'] / x['ev'] - 1) * 100:5.1f} {x['mono']:8d} {x['r3']:8d}  {others}")
        assert x["r2"] >= x["ev"] and x["mono"] >= x["ev"] and x["r3"] >= x["ev"]
        assert x["mono"] <= max_gems

    # Gegenprobe Arbitrage: Ausgaben für Kisten, bis das Item im Mittel einmal fällt, gegen Direktpreis.
    print("\n== Arbitrage: Kosten je erwartetem Exemplar über Kisten (Einzel / 10er-Paket) ==")
    for x in rows:
        ev = x["ev"]
        print(f"  {x['id']:26s} Kiste {float(ev):12,.1f} / {float(ev * 10 / 11):12,.1f}   Direkt {x['mono']:8,d}"
              f"   Direkt >= Kiste: {x['mono'] >= ev}")

    # Wert einer Eisenkiste zu Direktpreisen (für den Tag-7-Ersatz).
    iron = gem_crates["iron"]
    by_id = {x["id"]: x for x in rows}
    val_ev = sum(rates["iron"][r] / len(pools[("iron", r)]) * by_id[i]["ev"]
                 for (c, r), ids in pools.items() if c == "iron" for i in ids)
    val_px = sum(rates["iron"][r] / len(pools[("iron", r)]) * by_id[i]["mono"]
                 for (c, r), ids in pools.items() if c == "iron" for i in ids)
    eff = sum(rates["iron"][r] / len(pools[("iron", r)]) * by_id[i]["effectBp"]
              for (c, r), ids in pools.items() if c == "iron" for i in ids)
    print(f"\n== Eisenkiste (Tag 7): Preis {iron['price']} Gems ==")
    print(f"  Inhalt zu Direkt-EV bewertet: {float(val_ev):,.1f} Gems, zu Shoppreisen (monoton): {float(val_px):,.1f}")
    print(f"  Erwarteter effectBp je Öffnung: {float(eff):.1f} (Ungewöhnlich = 700)")
    print(f"\n== maxGems (Economy.purchases) = {max_gems:,d}; teuerstes Item {max(x['mono'] for x in rows):,d} ==")


if __name__ == "__main__":
    main()
