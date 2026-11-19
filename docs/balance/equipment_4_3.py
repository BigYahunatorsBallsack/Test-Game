#!/usr/bin/env python3
"""Paket 4.3: Kisten-Items wirken auf die Sammelrate (Ausrüstung, Sterne, Verschmelzen).

Aufruf: python3 docs/balance/equipment_4_3.py   (nur Standardbibliothek, feste Seeds ab 4300,
Laufzeit etwa 30 s). Liest Quoten und Pools direkt aus src/shared/Data/Crates.luau und
CrateItems.luau; Baum und Schleife kommen aus skilltree_2_1.py (Fassung ohne Tore).

Entwurf (Auftrag 4.3, noch nicht in den Daten):
  Sammelrate = Werkzeug x (1 + Baum) x (1 + Summe der drei Item-Boni)
  Slots: skin, companion, toolVariant, je ein Item.
  Grundwert bei Stern 1: common 5 %, uncommon 7 %, rare 10 %, epic 14 %, legendary 19 %, mythic 25 %.
  Jeder Stern über 1 gibt +15 % des Grundwerts (Stern 5 = 1,6-fach).
  Verschmelzen verbraucht für Stern n -> n+1 die Kopien STEP_COPIES[n-1] (1, 2, 3, 4),
  also 1, 2, 4, 7, 11 Exemplare insgesamt für Stern 1 bis 5.
Annahmen:
  - Der Spieler verschmilzt sofort und optimal und rüstet je Slot das Item mit dem höchsten Bonus aus.
  - Goldkiste mit Pity 15/60 wie in crates_4_2.py, Start mit frischem Zähler (0, 0).
  - Innerhalb einer Seltenheit ist jedes Item des Kisten-Pools gleich wahrscheinlich (CrateRoll.roll).
  - Gems je Öffnung: einzeln 400, im 10er-Paket 4000/11 = 363,6. Robux: bestes Gem-Paket
    (7.000 Gems für 2.499 Robux = 0,357 Robux je Gem).
  - Lauf-1-Simulation: Schleife und Kaufregel aus skilltree_2_1.py (5 s Weg je Richtung, billigster
    sichtbarer Knoten, Glück-Ast eingeschlossen, ohne Tore). Der Item-Faktor wirkt nur auf die
    Sammelrate, nicht auf Tank oder Preis.
"""
from __future__ import annotations

import bisect
import os
import random
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import skilltree_2_1 as st  # noqa: E402

RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
DE = {"common": "Gewöhnlich", "uncommon": "Ungewöhnlich", "rare": "Selten", "epic": "Episch",
      "legendary": "Legendär", "mythic": "Mythisch"}
SLOTS = ["skin", "companion", "toolVariant"]

# ---------------------------------------------------------------- Entwurf
BASE_BP = {"common": 500, "uncommon": 700, "rare": 1000, "epic": 1400, "legendary": 1900, "mythic": 2500}
STAR_STEP = 0.15                 # +15 % des Grundwerts je Stern über 1
STEP_COPIES = [1, 2, 3, 4]       # Kopien für 1->2, 2->3, 3->4, 4->5
MAX_STARS = 5

GEMS_SINGLE = 400
GEMS_BUNDLE = 4000 / 11
ROBUX_PER_GEM = 2499 / 7000
WOOD_COINS = 25_000
IRON_GEMS = 100
TREE_RATE_BP = 112_500           # Summe der Sammelrate-Knoten (+1.125 %)


# ---------------------------------------------------------------- Daten lesen
def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def load_odds():
    src = read("src/shared/Data/Crates.luau")
    odds = {}
    for crate in ("wood", "iron", "gold"):
        block = re.search(crate + r"\s*=\s*\{(.*?)\}", src, re.S).group(1)
        odds[crate] = {r: int(re.search(r + r"\s*=\s*(\d+)", block).group(1)) for r in RARITIES}
    return odds


def load_items():
    src = read("src/shared/Data/CrateItems.luau")
    items = []
    pat = re.compile(r'\{\s*id = "([^"]+)", kind = "([^"]+)", name = "[^"]*", rarity = "([^"]+)", '
                     r'crates = \{([^}]*)\}')
    for m in pat.finditer(src):
        crates = re.findall(r'"([^"]+)"', m.group(4))
        items.append({"id": m.group(1), "kind": m.group(2), "rarity": m.group(3), "crates": crates})
    return items


ODDS = load_odds()
ITEMS = load_items()
ITEM = {it["id"]: it for it in ITEMS}
POOL = {}
for it in ITEMS:
    for c in it["crates"]:
        POOL.setdefault(c, {}).setdefault(it["rarity"], []).append(it["id"])


# ---------------------------------------------------------------- Bonus-Modell
def cum_copies(step):
    out, s = [1], 1
    for c in step:
        s += c
        out.append(s)
    return out          # Exemplare für Stern 1..5


def stars_of(count, step=STEP_COPIES):
    cc = cum_copies(step)
    s = 0
    for i, need in enumerate(cc):
        if count >= need:
            s = i + 1
    return s


def item_bp(item_id, count, step=STEP_COPIES, base=BASE_BP):
    s = stars_of(count, step)
    if s == 0:
        return 0.0
    return base[ITEM[item_id]["rarity"]] * (1 + STAR_STEP * (s - 1))


def total_bp(inv, step=STEP_COPIES, base=BASE_BP):
    best = {k: 0.0 for k in SLOTS}
    for iid, n in inv.items():
        k = ITEM[iid]["kind"]
        b = item_bp(iid, n, step, base)
        if b > best[k]:
            best[k] = b
    return sum(best.values()), best


# ---------------------------------------------------------------- Kisten würfeln
def cdf(table, allowed):
    tot = sum(table[r] for r in allowed if table[r] > 0)
    acc, out = 0, []
    for r in allowed:
        if table[r] > 0:
            acc += table[r]
            out.append((acc / tot, r))
    return out


CDF = {c: cdf(ODDS[c], RARITIES) for c in ODDS}
CDF_E = cdf(ODDS["gold"], ["epic", "legendary", "mythic"])
CDF_L = cdf(ODDS["gold"], ["legendary", "mythic"])


def pick(cd, r):
    for p, rar in cd:
        if r < p:
            return rar
    return cd[-1][1]


class Opener:
    """Öffnet Kisten wie CrateRoll (Seltenheit, dann gleichverteilt im Pool), Gold mit Pity 15/60."""

    def __init__(self, rng, inv=None):
        self.rng = rng
        self.inv = dict(inv or {})
        self.e = 0
        self.l = 0

    def open(self, crate):
        r = self.rng.random()
        if crate in ("gold", "event"):
            cd = CDF_L if self.l == 59 else CDF_E if self.e == 14 else CDF["gold"]
            rar = pick(cd, r)
            if rar in ("legendary", "mythic"):
                self.e = self.l = 0
            elif rar == "epic":
                self.e, self.l = 0, self.l + 1
            else:
                self.e, self.l = self.e + 1, self.l + 1
        else:
            rar = pick(CDF[crate], r)
        pool = POOL[crate][rar]
        iid = pool[int(self.rng.random() * len(pool))]
        self.inv[iid] = self.inv.get(iid, 0) + 1
        return rar


def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def run_curve(crate, checkpoints, trials, seed, inv0=None, step=STEP_COPIES, base=BASE_BP):
    rng = random.Random(seed)
    res = {n: [] for n in checkpoints}
    slot_rar = {n: {k: {} for k in SLOTS} for n in checkpoints}
    top = max(checkpoints)
    for _ in range(trials):
        op = Opener(rng, inv0)
        for i in range(1, top + 1):
            op.open(crate)
            if i in res:
                tb, best = total_bp(op.inv, step, base)
                res[i].append(tb)
                # Seltenheit des ausgerüsteten Items je Slot
                for k in SLOTS:
                    cands = [(item_bp(iid, c, step, base), ITEM[iid]["rarity"])
                             for iid, c in op.inv.items() if ITEM[iid]["kind"] == k]
                    rr = max(cands)[1] if cands else "-"
                    slot_rar[i][k][rr] = slot_rar[i][k].get(rr, 0) + 1
    return res, slot_rar


# ---------------------------------------------------------------- Gold: Zyklen bis Legendär+
def cycle_length_dist():
    """Exakte Verteilung der Öffnungen bis Legendär+ ab (0, 0) mit Pity 15/60."""
    t = ODDS["gold"]
    tot = sum(t.values())
    pn_leg = (t["legendary"] + t["mythic"]) / tot
    pn_epic = t["epic"] / tot
    te = t["epic"] + t["legendary"] + t["mythic"]
    pe_leg = (t["legendary"] + t["mythic"]) / te
    mass = {(0, 0): 1.0}
    dist = []
    for n in range(1, 61):
        hit, nxt = 0.0, {}
        for (e, l), p in mass.items():
            if l == 59:
                hit += p
                continue
            if e == 14:
                hit += p * pe_leg
                key = (0, l + 1)
                nxt[key] = nxt.get(key, 0) + p * (1 - pe_leg)
                continue
            hit += p * pn_leg
            k1, k2 = (0, l + 1), (e + 1, l + 1)
            nxt[k1] = nxt.get(k1, 0) + p * pn_epic
            nxt[k2] = nxt.get(k2, 0) + p * (1 - pn_leg - pn_epic)
        dist.append(hit)
        mass = nxt
    return dist


CYC = cycle_length_dist()
CYC_MEAN = sum((i + 1) * p for i, p in enumerate(CYC))
CYC_CDF = []
_acc = 0.0
for _p in CYC:
    _acc += _p
    CYC_CDF.append(_acc)
P_MYTH_GIVEN_LP = ODDS["gold"]["mythic"] / (ODDS["gold"]["legendary"] + ODDS["gold"]["mythic"])


def sample_openings(rng, k):
    """Summe von k unabhängigen Zykluslängen."""
    s = 0
    for _ in range(k):
        s += bisect.bisect_left(CYC_CDF, rng.random() * CYC_CDF[-1]) + 1
    return s


def lp_milestone(cond, trials, seed, step=STEP_COPIES):
    """Legendär+-Treffer bis `cond(counts)` gilt; Ergebnis: Öffnungen je Versuch."""
    rng = random.Random(seed)
    leg, myth = POOL["gold"]["legendary"], POOL["gold"]["mythic"]
    out = []
    for _ in range(trials):
        cnt = {}
        k = 0
        while not cond(cnt, step):
            k += 1
            pool = myth if rng.random() < P_MYTH_GIVEN_LP else leg
            iid = pool[int(rng.random() * len(pool))]
            cnt[iid] = cnt.get(iid, 0) + 1
        out.append(sample_openings(rng, k))
    return out


def need(step):
    return cum_copies(step)[-1]


def c_first_myth(c, step):
    return any(ITEM[i]["rarity"] == "mythic" for i in c)


def c_one_myth5(c, step):
    return any(ITEM[i]["rarity"] == "mythic" and n >= need(step) for i, n in c.items())


def c_all_leg5(c, step):
    return all(c.get(i, 0) >= need(step) for i in POOL["gold"]["legendary"])


def c_all_myth5(c, step):
    return all(c.get(i, 0) >= need(step) for i in POOL["gold"]["mythic"])


def c_all_myth1(c, step):
    return all(c.get(i, 0) >= 1 for i in POOL["gold"]["mythic"])


# ---------------------------------------------------------------- Lauf 1 mit Item-Faktor
class ItemPlayer(st.Player):
    def __init__(self, item_bp=0, **kw):
        super().__init__(nodes=st.NODES_NO_GATES, buy_luck=True, **kw)
        self.item_mult = 1 + item_bp / 10000

    @property
    def rate(self):
        return st.Player.rate.fget(self) * self.item_mult


def sim_run(item_bp=0, **kw):
    p = ItemPlayer(item_bp=item_bp, **kw)
    while p.t < st.MAX_SIM_S and not p.done():
        p.run()
    tm = {}
    for t, i, _, _ in p.log:
        tm.setdefault(i, t)
    gaps = [b[0] - a[0] for a, b in zip([(0.0,)] + p.log[:-1], p.log)]
    lens = [r[4] for r in p.runs]
    band = sum(x for x in lens if st.RUN_BAND[0] <= x <= st.RUN_BAND[1]) / sum(lens)
    short = sum(1 for x in lens if x < st.RUN_BAND[0]) / len(lens)
    return p, tm, max(gaps), band, short


def income_at(p, t):
    """Mittlerer Ertrag pro Sekunde des Laufs, der um Zeitpunkt t endet."""
    best = None
    for r in p.runs:
        if r[0] <= t:
            best = r
    return best[5] / best[4] if best else 0.0


# ---------------------------------------------------------------- Ausgabe
def pct(bp):
    return f"{bp / 100:.1f} %".replace(".", ",")


def num(x):
    return f"{x:,.0f}".replace(",", ".")


def main():
    print("Pools je Kiste (Anzahl Items je Seltenheit):")
    for c in ("wood", "iron", "gold", "event"):
        slots = {k: sum(1 for r in POOL[c].values() for i in r if ITEM[i]["kind"] == k) for k in SLOTS}
        print(f"  {c:<6}", {r: len(POOL[c].get(r, [])) for r in RARITIES}, "Slots:", slots)
    print()
    print("Bonus je Seltenheit und Stern (Entwurf):")
    for r in RARITIES:
        row = [BASE_BP[r] * (1 + STAR_STEP * (s - 1)) for s in range(1, 6)]
        print(f"  {DE[r]:<13}", "  ".join(pct(x) for x in row))
    print(f"  Exemplare für Stern 1..5: {cum_copies(STEP_COPIES)}")
    print(f"  Maximum 3 x Mythisch Stern 5: {pct(3 * BASE_BP['mythic'] * 1.6)}; "
          f"Rate-Faktor am Baumende ohne Items {1 + TREE_RATE_BP / 10000:.2f}, mit +120 % "
          f"{(1 + TREE_RATE_BP / 10000) * 2.2:.2f}")
    print()

    # (a) Kurven
    T = 20000
    print(f"(a) Gesamtbonus nach N Öffnungen ({T} Versuche je Kiste)")
    scen = [("gold", [10, 11, 50, 55, 200], 4301, None, "Gold"),
            ("wood", [100, 1000, 3000], 4302, None, "Holz"),
            ("iron", [100, 500, 1000], 4303, None, "Eisen")]
    wood_floor = {"companion_epic_1": 11, "skin_epic_1": 11}
    scen.append(("gold", [10, 50, 200], 4304, wood_floor, "Gold auf Holz-Deckel (44,8 %)"))
    for crate, cps, seed, inv0, label in scen:
        trials = T if max(cps) <= 1000 else 4000
        res, sr = run_curve(crate, cps, trials, seed, inv0)
        for n in cps:
            xs = res[n]
            cost = (f"{num(n * GEMS_BUNDLE)} Gems (Paket) / {num(n * GEMS_SINGLE)} einzeln"
                    if crate != "wood" else f"{num(n * WOOD_COINS)} Münzen")
            if crate == "iron":
                cost = f"{num(n * IRON_GEMS * 10 / 11)} Gems (Paket)"
            print(f"  {label:<30} N={n:>5}  Median {pct(q(xs, .5)):>8}  P10 {pct(q(xs, .1)):>8}  "
                  f"P90 {pct(q(xs, .9)):>8}  Mittel {pct(statistics.mean(xs)):>8}   {cost}")
            for k in SLOTS:
                d = sr[n][k]
                tot = sum(d.values())
                top = sorted(d.items(), key=lambda x: -x[1])[:3]
                print(f"      {k:<12}", ", ".join(f"{DE.get(r, r)} {v / tot:.0%}" for r, v in top))
    print()

    # (b) Meilensteine Gold
    print(f"(b) Goldkiste: Öffnungen bis Meilenstein (Zyklus-Mittel {CYC_MEAN:.3f}, "
          f"P(Mythisch | Legendär+) = {P_MYTH_GIVEN_LP:.2f})")
    ms = [("erstes Mythisch (beliebig)", c_first_myth),
          ("alle 3 Mythisch Stern 1 (+75 %)", c_all_myth1),
          ("alle 3 Legendär Stern 5 (+91,2 %)", c_all_leg5),
          ("ein Mythisch Stern 5", c_one_myth5),
          ("alle 3 Mythisch Stern 5 (+120 %)", c_all_myth5)]
    for name, cond in ms:
        xs = lp_milestone(cond, 20000, 4310)
        m = statistics.mean(xs)
        print(f"  {name:<36} Mittel {num(m):>7}  Median {num(q(xs, .5)):>7}  P90 {num(q(xs, .9)):>7}"
              f"  -> {num(m * GEMS_BUNDLE):>10} Gems (Paket) = {num(m * GEMS_BUNDLE * ROBUX_PER_GEM):>8} Robux"
              f"  | P90 {num(q(xs, .9) * GEMS_BUNDLE * ROBUX_PER_GEM)} Robux")
    print()

    # (c) Kopien je Seltenheit
    print("(c) Öffnungen bis Stern 5 eines bestimmten Items (11 Exemplare), Erwartung 11 / Rate je Item")
    eff = {"uncommon": 0.395588, "rare": 0.395588, "epic": 0.154955, "legendary": 0.048481, "mythic": 0.005387}
    for crate in ("wood", "iron", "gold"):
        for r in RARITIES:
            n = len(POOL[crate].get(r, []))
            p = (eff[r] if crate == "gold" and r in eff else ODDS[crate][r] / 10000) if n else 0
            if crate == "gold" and r == "common":
                p = 0
            if p <= 0:
                continue
            per = p / n
            print(f"  {crate:<5} {DE[r]:<13} Rate je Item {per:7.3%}  Öffnungen bis Stern 2/3/5: "
                  f"{num(2 / per)}/{num(4 / per)}/{num(11 / per)}")
    print()
    alt = {"common": [2, 3, 4, 5], "uncommon": [2, 3, 4, 5], "rare": [1, 2, 3, 4], "epic": [1, 2, 3, 4],
           "legendary": [1, 2, 2, 3], "mythic": [1, 1, 2, 2]}
    print("    Gestaffelt (Vorschlag):", {r: cum_copies(v)[-1] for r, v in alt.items()})
    variants = [("Mythisch [1,1,2,2]", [1, 1, 2, 2], c_one_myth5, c_all_myth5),
                ("Mythisch [1,1,1,1]", [1, 1, 1, 1], c_one_myth5, c_all_myth5),
                ("Legendär [1,2,2,3]", [1, 2, 2, 3], None, c_all_leg5)]
    for label, stp, one, allc in variants:
        for name, cond in (("ein Item Stern 5", one), ("alle 3 Stern 5", allc)):
            if cond is None:
                continue
            xs = lp_milestone(cond, 20000, 4320, step=stp)
            m = statistics.mean(xs)
            print(f"    {label:<20} {name:<17} Mittel {num(m):>6} Öffnungen = {num(m * GEMS_BUNDLE):>9} Gems"
                  f" = {num(m * GEMS_BUNDLE * ROBUX_PER_GEM):>7} Robux")
    print()

    # Lauf 1 mit Item-Faktor
    print("Lauf 1 (ohne Tore, Glück-Ast gekauft) mit Item-Bonus auf die Sammelrate")
    rows = [(0, {}), (2900, {}), (4480, {}), (6720, {}), (9120, {}), (12000, {}),
            (0, {"coin_mult": 2.0}), (12000, {"coin_mult": 2.0}),
            (0, {"autodig": True}), (12000, {"autodig": True})]
    base_end = None
    for bp, kw in rows:
        p, tm, gap, band, short = sim_run(bp, **kw)
        end = p.log[-1][0]
        base_end = base_end or end
        tag = ("2x Münzen " if kw.get("coin_mult") else "") + ("Auto-Dig " if kw.get("autodig") else "")
        print(f"  {tag:<11}Items {pct(bp):>8}: Upgrade1 {st.fmt_t(tm['collect_rate_1']):>5}  "
              f"Schaufel {st.fmt_t(tm['collect_tool_2']):>5}  Eimer {st.fmt_t(tm['collect_tool_3']):>5}  "
              f"Bagger {st.fmt_t(tm['collect_tool_4']):>5}  Saug {st.fmt_t(tm['collect_tool_5']):>5}  "
              f"Groß {st.fmt_t(tm['collect_tool_6']):>5}  Ende {st.fmt_t(end):>5} ({end / base_end - 1:+.0%})  "
              f"längste Pause {gap:4.0f} s  Spielzeit im Band {band:.0%}  Läufe <15 s {short:.0%}")
    print()

    # (d) Holzkiste
    p, tm, *_ = sim_run(0)
    print("(d) Holzkiste in Lauf 1 (Basis): Kosten einer Kiste in Sekunden Ertrag")
    for label, node in [("Schaufel", "collect_tool_2"), ("Eimerkette", "collect_tool_3"),
                        ("Mini-Bagger", "collect_tool_4"), ("Saugroboter", "collect_tool_5"),
                        ("Großmaschine", "collect_tool_6")]:
        t = tm[node] + 60
        inc = income_at(p, t)
        print(f"  {label:<13} (1 min danach, {st.fmt_t(t)}): {num(inc):>11} Münzen/s -> 1 Kiste "
              f"{WOOD_COINS / inc:8.2f} s, 10er-Paket {10 * WOOD_COINS / inc:8.2f} s")
    end_inc = income_at(p, p.log[-1][0] + 1)
    first_free = next((r[0] for r in p.runs if r[5] / r[4] >= WOOD_COINS), None)
    print(f"  Ertrag >= 25.000 Münzen/s (1 Kiste < 1 s) ab {st.fmt_t(first_free)}; Baumende-Ertrag {num(end_inc)}/s")
    # Kosten bis Holz-Deckel
    rng = random.Random(4330)
    xs = []
    for _ in range(20000):
        op = Opener(rng)
        n = 0
        while not (op.inv.get("companion_epic_1", 0) >= 11 and
                   max(op.inv.get("skin_epic_1", 0), op.inv.get("skin_epic_2", 0)) >= 11):
            op.open("wood")
            n += 1
        xs.append(n)
    m = statistics.mean(xs)
    print(f"  Holz-Deckel (Skin + Begleiter Episch Stern 5 = 44,8 %): Mittel {num(m)} Öffnungen, "
          f"P90 {num(q(xs, .9))}; Münzen (Paket) {num(m * WOOD_COINS * 10 / 11)} = "
          f"{m * WOOD_COINS * 10 / 11 / end_inc:.0f} s Baumende-Ertrag Lauf 1; "
          f"{m / 11:.0f} Paket-Aufrufe x 1,3 s = {m / 11 * 1.3 / 60:.1f} min")
    print("  BigNum: sub(coins, 25.000) fällt weg, wenn Exponent(coins) - 4 > 15, also ab 10^20 Münzen.")
    for per_day in (11, 33, 110):
        print(f"  Tageslimit {per_day:>3} Öffnungen: 100 Öffnungen nach {100 / per_day:5.1f} Tagen, 1.000 nach "
              f"{1000 / per_day:5.1f}, Holz-Deckel (Mittel) nach {m / per_day:5.0f} Tagen")
    for price in (25_000, 250_000, 2_500_000, 25_000_000):
        print(f"  Preis {num(price):>11}: Holz-Deckel kostet {num(m * price * 10 / 11):>16} Münzen"
              f" = {m * price * 10 / 11 / 2.14e9:6.2f} x Lauf-1-Verdienst (2,14 Mrd.)")


if __name__ == "__main__":
    main()
