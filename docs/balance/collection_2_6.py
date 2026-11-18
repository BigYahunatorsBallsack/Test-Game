#!/usr/bin/env python3
"""Dune Baron, Paket 2.6: Fundstücke, Sets und Sammlungsbonus.

Fragen (Bericht: docs/balance/collection_2_6.md):
  1. Sammelzeit bis jedes Set einer Zone fertig ist (Coupon-Collector mit den echten
     Wahrscheinlichkeiten), ohne Glück und mit vollem Glück-Ast (x2): Mittel und 90. Perzentil.
  2. Taugt die Seltenheitsverteilung der Sets? Vergleich mit Alternativen.
  3. Sammlungsbonus (Data/Collection.setBonusBp) im ersten Lauf: Werkzeugzeiten höchstens 10 % kürzer.
  4. Anteil der Münzen aus verkauften Duplikaten je Werkzeug, mit und ohne Sammlungsbonus.
  5. Zu schnell, zu langsam, Ausnutzungswege.

Modell der Funde (wie src/shared/Logic/FindRoll.luau):
  Chance pro Sammelsekunde = findChancePerSecond x Zonenfaktor x Glück-Ast x (1 + Regen-Bonus x Stärke).
  Seltenheit nach FindOdds.tables.base, danach gleich verteilt unter den Funden der Zone mit dieser
  Seltenheit. Erster Fund sicher nach 60 s Sammeln (Gewöhnlich). Doppelte Funde werden sofort zum
  festen Wert verkauft: 3 x Sandfaktor x Werkzeug-Grundrate x Wertfaktor, ohne Knoten-Boni, ohne
  Sammlungsbonus und ohne 2x Münzen (Collection.record bucht den Wert direkt).
  Ein Poisson-Prozess mit dieser Rate ist exakt das Grenzverhalten von 1 - (1 - p)^dt pro Tick.

Der erste Lauf nutzt Baum, Schleife und Kaufregel aus docs/balance/skilltree_2_1.py (Import),
mit Glück-Ast. Nur Standardbibliothek, feste Seeds. Aufruf: python3 docs/balance/collection_2_6.py
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import skilltree_2_1 as st  # noqa: E402

# ---------------------------------------------------------------------------
# Daten (src/shared/Data: FindOdds, Rarities, Weather, Collection, SandTypes, Zones)
# ---------------------------------------------------------------------------

FIND_CHANCE = 0.02                      # FindOdds.findChancePerSecond = 200 bp
FIRST_FIND_S = 60                       # FindOdds.firstFindGuaranteeSeconds
FIND_BASE_VALUE = 3                     # FindOdds.findBaseValue
RARITY = ["c", "u", "r", "e", "l", "m"]
RARITY_NAME = {"c": "Gewöhnlich", "u": "Ungewöhnlich", "r": "Selten", "e": "Episch",
               "l": "Legendär", "m": "Mythisch"}
ODDS = {"c": 0.70, "u": 0.22, "r": 0.06, "e": 0.016, "l": 0.0035, "m": 0.0005}
VALUE = {"c": 1, "u": 4, "r": 15, "e": 60, "l": 300, "m": 1500}

ZONES = ["dunes", "oasis", "canyon", "salt_lake", "ruins"]
ZONE_NAME = {"dunes": "Dünenmeer", "oasis": "Oase", "canyon": "Canyon", "salt_lake": "Salzsee",
             "ruins": "Ruinenstadt"}
ZONE_FACTOR = {"dunes": 1.0, "oasis": 1.2, "canyon": 1.4, "salt_lake": 1.6, "ruins": 2.0}
SAND_FACTOR = {"dunes": 1, "oasis": 3, "canyon": 10, "salt_lake": 40, "ruins": 150}

# Regen in der Oase (Data/Weather): 90 s aktiv je 480 s, +15 %, 4 s Ein- und Ausblenden.
RAIN = dict(cycle=480.0, active=90.0, offset=0.0, bonus=0.15, fade=4.0)
RAIN_AVG = 1 + RAIN["bonus"] * (RAIN["active"] - RAIN["fade"]) / RAIN["cycle"]


def rain_strength(t):
    ph = (t - RAIN["offset"]) % RAIN["cycle"]
    if ph >= RAIN["active"]:
        return 0.0
    return min(min(max(ph / RAIN["fade"], 0), 1), min(max((RAIN["active"] - ph) / RAIN["fade"], 0), 1))


def weather_avg(zone):
    return RAIN_AVG if zone == "oasis" else 1.0


# Sets je Zone: Liste der Seltenheiten je Set (in jeder Zone gleich).
LAYOUTS = {
    "Entwurf": [
        "cccuu",   # Set 1: 3c 2u
        "ccuur",   # Set 2: 2c 2u 1r
        "cuurr",   # Set 3: 1c 2u 2r
        "uurre",   # Set 4: 2u 2r 1e
        "urrel",   # Set 5: 1u 2r 1e 1l
        "reelm",   # Set 6: 1r 2e 1l 1m
    ],
    # Vorschlag V1: Set 1 nur Gewöhnliche, die zwei Ungewöhnlichen wandern in Set 2 und 3.
    "V1 (Set 1 = 5c)": [
        "ccccc",
        "cuuur",
        "uuurr",
        "uurre",
        "urrel",
        "reelm",
    ],
}

# Sammlungsbonus je Set-Nummer (bp). "Start" = Data/Collection.luau vor 2.6-Balance.
BONUS = {
    "aus": [0, 0, 0, 0, 0, 0],
    "Start": [200, 200, 300, 300, 500, 1000],
    "Final": [300, 300, 400, 400, 600, 1000],
    "Stress x4": [800, 800, 1200, 1200, 2000, 4000],
}
FINAL = "Final"

# Annahmen für den Sandsturm-Rhythmus
PLAY_MIN_PER_DAY = 15.0      # zwei Sitzungen à 7,5 min (Konzept: 5 bis 10 min, tägliche Rückkehr)
TRIALS_SET = 20000           # Monte Carlo je Zone und Glück (Prüfung der analytischen Werte)
TRIALS_RUN = 1000            # Monte Carlo erster Lauf je Variante


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

def item_probs(layout):
    """Wahrscheinlichkeit je Fund für jeden Slot: Seltenheit, dann gleich verteilt in der Zone."""
    count = {r: 0 for r in RARITY}
    for s in layout:
        for r in s:
            count[r] += 1
    return [[ODDS[r] / count[r] for r in s] for s in layout], count


def fmt_dur(s):
    if s is None or s != s:
        return "-"
    s = int(round(s))
    if s < 3600:
        return f"{s // 60}:{s % 60:02d} min"
    h, rem = divmod(s, 3600)
    return f"{h}:{rem // 60:02d} h"


def fmt_pct(x, d=1):
    return f"{x * 100:.{d}f} %".replace(".", ",")


def pct(values, q):
    v = sorted(values)
    if not v:
        return float("nan")
    k = min(len(v) - 1, max(0, int(math.ceil(q * len(v))) - 1))
    return v[k]


# ---------------------------------------------------------------------------
# 1. Coupon-Collector: analytisch (Poisson-Prozesse je Slot) und Monte Carlo
# ---------------------------------------------------------------------------

def cdf_max(rates, t):
    out = 1.0
    for q in rates:
        out *= 1 - math.exp(-q * t)
    return out


def mean_max(rates):
    """E[max Exp(q_i)] = Integral (1 - Prod(1 - e^-q t)) dt, numerisch auf Log-Gitter."""
    qmin, qmax = min(rates), max(rates)
    lo, hi = math.log(1e-4 / qmax), math.log(60 / qmin)
    n = 6000
    du = (hi - lo) / n
    total = 0.0
    prev = None
    for k in range(n + 1):
        t = math.exp(lo + k * du)
        f = (1 - cdf_max(rates, t)) * t
        if prev is not None:
            total += (prev + f) / 2 * du
        prev = f
    return total + math.exp(lo)  # Anteil unter der Untergrenze (Integrand dort 1)


def quantile_max(rates, q):
    lo, hi = 0.0, 100 / min(rates)
    for _ in range(100):
        mid = (lo + hi) / 2
        if cdf_max(rates, mid) < q:
            lo = mid
        else:
            hi = mid
    return hi


def set_rates(layout, lam):
    probs, _ = item_probs(layout)
    return [[lam * p for p in s] for s in probs]


def analytic_table(layout, lam):
    rates = set_rates(layout, lam)
    rows = []
    for s in rates:
        rows.append((mean_max(s), quantile_max(s, 0.9)))
    allr = [q for s in rates for q in s]
    rows.append((mean_max(allr), quantile_max(allr, 0.9)))
    return rows


def mc_sets(layout, lam, trials, seed, first_find=True):
    """Ankunftszeit je Slot ~ Exp(lam p). Erster Fund sicher bei 60 s (zufälliger Gewöhnlicher)."""
    rng = random.Random(seed)
    probs, count = item_probs(layout)
    flat = [(si, r, p) for si, s in enumerate(layout) for r, p in zip(s, probs[si])]
    commons = [k for k, (_, r, _) in enumerate(flat) if r == "c"]
    res = [[] for _ in range(len(layout) + 1)]
    for _ in range(trials):
        times = [rng.expovariate(lam * p) for _, _, p in flat]
        # alle Funde zusammen kommen mit Rate lam; der erste natürliche Fund
        first = rng.expovariate(lam)
        if first_find and first > FIRST_FIND_S:
            k = rng.choice(commons)
            times[k] = min(times[k], FIRST_FIND_S)
        per = [0.0] * len(layout)
        for (si, _, _), t in zip(flat, times):
            per[si] = max(per[si], t)
        for si, t in enumerate(per):
            res[si].append(t)
        res[-1].append(max(per))
    return res


def mc_sets_newfirst(layout, lam, trials, seed):
    """Logik-Option (nicht im Code): gewürfelte Seltenheit füllt zuerst den fehlenden Slot
    dieser Seltenheit im niedrigsten Set, erst danach gibt es Duplikate."""
    rng = random.Random(seed)
    order = {r: [si for si, s in enumerate(layout) for x in s if x == r] for r in RARITY}
    cum = [(ODDS[r], r) for r in RARITY]
    res = [[] for _ in range(len(layout) + 1)]
    finds_needed = [[] for _ in range(len(layout) + 1)]
    for _ in range(trials):
        have = {r: 0 for r in RARITY}
        missing = [len(s) for s in layout]
        done = [None] * len(layout)
        t = 0.0
        n = 0
        left = len(layout)
        while left:
            t += rng.expovariate(lam)
            n += 1
            x = rng.random()
            acc = 0.0
            rr = "m"
            for p, r in cum:
                acc += p
                if x < acc:
                    rr = r
                    break
            if have[rr] < len(order[rr]):
                si = order[rr][have[rr]]
                have[rr] += 1
                missing[si] -= 1
                if missing[si] == 0:
                    done[si] = (t, n)
                    left -= 1
        for si, (tt, nn) in enumerate(done):
            res[si].append(tt)
            finds_needed[si].append(nn)
        res[-1].append(max(d[0] for d in done))
        finds_needed[-1].append(max(d[1] for d in done))
    return res, finds_needed


def lam_of(zone, luck):
    return FIND_CHANCE * ZONE_FACTOR[zone] * luck * weather_avg(zone)


# ---------------------------------------------------------------------------
# 3. Erster Lauf mit Funden, Sammlung und Bonus (Baum und Schleife aus skilltree_2_1)
# ---------------------------------------------------------------------------

class FindPlayer(st.Player):
    def __init__(self, rng, layout, bonus, newfirst=False, find_rate_mult=1.0, **kw):
        kw.setdefault("buy_luck", True)
        super().__init__(**kw)
        self.rng = rng
        self.layout = layout
        self.bonus = bonus
        self.newfirst = newfirst
        self.find_rate_mult = find_rate_mult
        self.weather_offset = rng.uniform(0, RAIN["cycle"])
        self.cum_gather = 0.0
        self.found = {}            # (zone, set, slot) -> Anzahl
        self.sets_done = {}        # (zone, set) -> Zeit
        self.bonus_bp = 0
        self.dupe_coins = {}       # Werkzeug -> Münzen aus Duplikaten
        self.sand_coins = {}       # Werkzeug -> Münzen aus Sand
        self.finds = 0
        self.new_finds = 0
        self.gather_by_zone = {}
        self.luck_gather = 0.0
        probs, _ = item_probs(layout)
        self.by_rarity = {r: [(si, k) for si, s in enumerate(layout) for k, x in enumerate(s) if x == r]
                          for r in RARITY}

    @property
    def price(self):
        return st.Player.price.fget(self) * (10000 + self.bonus_bp) / 10000

    def _roll_rarity(self):
        x = self.rng.random()
        acc = 0.0
        for r in RARITY:
            acc += ODDS[r]
            if x < acc:
                return r
        return "m"

    def _find(self, zone, rarity, t):
        self.finds += 1
        slots = self.by_rarity[rarity]
        if self.newfirst:
            miss = [s for s in slots if (zone,) + s not in self.found]
            slot = miss[0] if miss else self.rng.choice(slots)
        else:
            slot = self.rng.choice(slots)
        key = (zone,) + slot
        if key in self.found:
            self.found[key] += 1
            v = FIND_BASE_VALUE * SAND_FACTOR[zone] * st.TOOL_RATE[self.tool] * VALUE[rarity]
            self.dupe_coins[self.tool] = self.dupe_coins.get(self.tool, 0.0) + v
            return v
        self.found[key] = 1
        self.new_finds += 1
        si = slot[0]
        if all((zone, si, k) in self.found for k in range(len(self.layout[si]))):
            self.sets_done[(zone, si)] = t
            self.bonus_bp += self.bonus[si]
        return 0.0

    def _gather_finds(self, zone, t_start, dur):
        """Funde in einem Sammelfenster [t_start, t_start + dur] (Wanduhr)."""
        coins = 0.0
        base = FIND_CHANCE * ZONE_FACTOR[zone] * self.luck * self.find_rate_mult
        top = base * (1 + RAIN["bonus"] if zone == "oasis" else 1)
        events = []
        x = 0.0
        while True:
            x += self.rng.expovariate(top)
            if x > dur:
                break
            if zone == "oasis":
                f = 1 + RAIN["bonus"] * rain_strength(t_start + x + self.weather_offset)
                if self.rng.random() >= f / (1 + RAIN["bonus"]):
                    continue
            events.append(x)
        guarantee = None
        if not self.found and self.cum_gather < FIRST_FIND_S <= self.cum_gather + dur:
            guarantee = FIRST_FIND_S - self.cum_gather
        done_guarantee = False
        for e in events:
            if guarantee is not None and not done_guarantee and e >= guarantee:
                if not self.found:
                    coins += self._find(zone, "c", t_start + guarantee)
                done_guarantee = True
            coins += self._find(zone, self._roll_rarity(), t_start + e)
        if guarantee is not None and not done_guarantee and not self.found:
            coins += self._find(zone, "c", t_start + guarantee)
        self.cum_gather += dur
        self.gather_by_zone[zone] = self.gather_by_zone.get(zone, 0.0) + dur
        self.luck_gather += self.luck * dur
        return coins

    def run(self):
        t0 = self.t
        cap, rate = self.capacity, self.rate
        start = min(cap, rate * st.WALK_ONE_WAY_S) if (self.autodig and self.runs) else 0.0
        gather = (cap - start) / rate
        zone = self.zone[0]
        tool = self.tool
        find_coins = self._gather_finds(zone, t0 - start / rate, gather + start / rate)
        self.t += gather + st.WALK_ONE_WAY_S
        sand = cap * self.price
        self.sand_coins[tool] = self.sand_coins.get(tool, 0.0) + sand
        earned = sand + find_coins
        self.coins += earned
        run_len = gather + 2 * st.WALK_ONE_WAY_S
        self.runs.append((self.t, tool, zone, gather, run_len, earned))
        self.buy(earned / run_len)
        self.t += st.WALK_ONE_WAY_S
        return t0


def first_run(seed, layout="Entwurf", bonus="Final", **kw):
    rng = random.Random(seed)
    p = FindPlayer(rng, LAYOUTS[layout], BONUS[bonus], **kw)
    while p.t < st.MAX_SIM_S and not p.done():
        p.run()
    main = [t for t, i, _, _ in p.log if p.node[i][3] != "luck"]
    p.end_t = main[-1] if main else None
    return p


MS = ["collect_rate_1", "collect_tool_2", "collect_tool_3", "collect_tool_4", "collect_tool_5",
      "collect_tool_6", "END"]


def run_batch(trials, base_seed, **kw):
    out = []
    for k in range(trials):
        p = first_run(base_seed + k, **kw)
        out.append(p)
    return out


def worst_case_run(sets_at_entry, bonus, nodes=None):
    """Obere Schranke: Set-Nummern in `sets_at_entry` sind fertig, sobald der Spieler eine Zone betritt."""
    class W(st.Player):
        @property
        def price(self):
            zones_seen = [z for z in st.ZONES if z[2] is None or z[2] in self.owned]
            bp = len(zones_seen) * sum(bonus[i] for i in sets_at_entry)
            return st.Player.price.fget(self) * (10000 + bp) / 10000
    p = W(buy_luck=True, nodes=nodes)
    while p.t < st.MAX_SIM_S and not p.done():
        p.run()
    main = [t for t, i, _, _ in p.log if p.node[i][3] != "luck"]
    p.end_t = main[-1] if main else None
    return p


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

def section(title):
    print()
    print("=" * 100)
    print(title)
    print("=" * 100)


def main():
    # ---------------------------------------------------------------- 1. Sets je Zone
    section("1. Sammelzeit bis Set fertig (echte Sammelzeit), Mittel / 90. Perzentil, Entwurf")
    print(f"  Regen Oase im Mittel: x{RAIN_AVG:.4f} (90 s je 480 s, 4 s Blende)")
    layout = LAYOUTS["Entwurf"]
    probs, count = item_probs(layout)
    print("  Slot-Wahrscheinlichkeit je Fund: " + ", ".join(
        f"{RARITY_NAME[r]} {count[r]} Slots je {fmt_pct(ODDS[r] / count[r], 3)}" for r in RARITY))
    for luck, label in ((1.0, "ohne Glück"), (2.0, "voller Glück-Ast x2")):
        print(f"\n  --- {label} ---")
        print(f"  {'Zone':<12}" + "".join(f"{'Set ' + str(i + 1):>22}" for i in range(6)) + f"{'Zonenbuch':>22}")
        for z in ZONES:
            rows = analytic_table(layout, lam_of(z, luck))
            print(f"  {ZONE_NAME[z]:<12}" + "".join(f"{fmt_dur(m) + ' / ' + fmt_dur(q):>22}" for m, q in rows))

    # Gegenprobe Monte Carlo (Dünenmeer, ohne Glück, mit "Erster Fund sicher")
    print("\n  Gegenprobe Monte Carlo Dünenmeer ohne Glück (Seed 26, 20.000 Läufe, mit erstem Fund sicher):")
    res = mc_sets(layout, lam_of("dunes", 1.0), TRIALS_SET, 26)
    print("   " + "  ".join(f"S{i + 1} {fmt_dur(sum(r) / len(r))} / {fmt_dur(pct(r, 0.9))}"
                            if i < 6 else f"Buch {fmt_dur(sum(r) / len(r))} / {fmt_dur(pct(r, 0.9))}"
                            for i, r in enumerate(res)))

    # Funde (Anzahl) je Set: zonenunabhängig
    print("\n  Erwartete Anzahl Funde bis Set fertig (gilt in jeder Zone, Glück ändert sie nicht):")
    rows = analytic_table(layout, 1.0)
    print("   " + "  ".join(f"S{i + 1} {m:,.0f} / {q:,.0f}".replace(",", ".") if i < 6 else
                            f"Buch {m:,.0f} / {q:,.0f}".replace(",", ".") for i, (m, q) in enumerate(rows)))

    # Ziel Set 1 Dünenmeer
    lam = lam_of("dunes", 1.0)
    s1 = set_rates(layout, lam)[0]
    print(f"\n  Set 1 Dünenmeer: P(fertig nach 20 min Sammeln) = {fmt_pct(cdf_max(s1, 1200))}, "
          f"nach 3:43 min (Sammelzeit im Dünenmeer im ersten Lauf) = {fmt_pct(cdf_max(s1, 223))}")

    # ---------------------------------------------------------------- 2. Verteilung
    section("2. Seltenheitsverteilung: Entwurf gegen V1 und Logik-Option 'neu zuerst' (Funde bis Set fertig)")
    print(f"  {'Variante':<36}" + "".join(f"{'Set ' + str(i + 1):>15}" for i in range(6)) + f"{'Buch':>15}")
    for name, lay in LAYOUTS.items():
        rows = analytic_table(lay, 1.0)
        print(f"  {name + ' (Funde, Mittel)':<36}" + "".join(f"{m:>15,.0f}".replace(",", ".") for m, _ in rows))
        print(f"  {name + ' (Funde, P90)':<36}" + "".join(f"{q:>15,.0f}".replace(",", ".") for _, q in rows))
    for name, lay in LAYOUTS.items():
        _, needed = mc_sets_newfirst(lay, 1.0, 4000, 27)
        print(f"  {'neu zuerst, ' + name + ' (Mittel)':<36}" + "".join(
            f"{sum(n) / len(n):>15,.0f}".replace(",", ".") for n in needed))
        print(f"  {'neu zuerst, ' + name + ' (P90)':<36}" + "".join(
            f"{pct(n, 0.9):>15,.0f}".replace(",", ".") for n in needed))
    print("\n  Dieselben Werte als Sammelzeit im Dünenmeer ohne Glück (Mittel / P90):")
    for name, lay in LAYOUTS.items():
        rows = analytic_table(lay, lam_of("dunes", 1.0))
        print(f"  {name:<36}" + "".join(f"{fmt_dur(m) + ' / ' + fmt_dur(q):>24}" for m, q in rows))
    for name, lay in LAYOUTS.items():
        res, _ = mc_sets_newfirst(lay, lam_of("dunes", 1.0), 4000, 28)
        print(f"  {'neu zuerst, ' + name:<36}" + "".join(
            f"{fmt_dur(sum(r) / len(r)) + ' / ' + fmt_dur(pct(r, 0.9)):>24}" for r in res))
    print("\n  Engpass je Set (seltenster Slot, Anteil je Fund):")
    for name, lay in LAYOUTS.items():
        pr, _ = item_probs(lay)
        print(f"  {name:<22}" + "  ".join(f"S{i + 1} {fmt_pct(min(s), 3)}" for i, s in enumerate(pr)))

    # ---------------------------------------------------------------- 3. Erster Lauf
    section("3. Erster Lauf mit Funden, Duplikatverkauf und Sammlungsbonus (Glück-Ast gekauft)")
    ref_g = st.times(st.simulate(buy_luck=True))
    ref_n = st.times(st.simulate(buy_luck=True, nodes=st.NODES_NO_GATES))
    print("  Referenz 2.1 mit Tor (Glück-Ast, ohne Fundwert): " +
          ", ".join(f"{st.MILESTONE_LABEL[m]} {st.fmt_t(ref_g[m])}" for m in MS))
    print("  Referenz ohne Tore (heutige UpgradeTree.luau):   " +
          ", ".join(f"{st.MILESTONE_LABEL[m]} {st.fmt_t(ref_n[m])}" for m in MS))

    variants = [
        ("Tore, Entwurf", dict(), ref_g),
        ("Tore, Entwurf, 2x Münzen", dict(coin_mult=2.0), None),
        ("Tore, Entwurf, Auto-Dig (obere Schranke)", dict(autodig=True), None),
        ("Tore, V1 (Set 1 = 5c)", dict(layout="V1 (Set 1 = 5c)"), ref_g),
        ("Tore, V1 + neu zuerst", dict(layout="V1 (Set 1 = 5c)", newfirst=True), ref_g),
        ("Ohne Tore (heute), Entwurf", dict(nodes=st.NODES_NO_GATES), ref_n),
        ("Ohne Tore (heute), V1 + neu zuerst", dict(nodes=st.NODES_NO_GATES, layout="V1 (Set 1 = 5c)",
                                                    newfirst=True), ref_n),
    ]
    summary = {}
    for vname, kw, ref in variants:
        print(f"\n  --- {vname} ({TRIALS_RUN} Läufe, Seeds 1000 ff.) ---")
        batches = {}
        for b in ("aus", "Start", FINAL, "Stress x4"):
            batches[b] = run_batch(TRIALS_RUN, 1000, bonus=b, **kw)
        base = batches["aus"]
        tb = [st.times(p) for p in base]
        print(f"  {'Bonus':<11}{'Meilenstein':<14}{'Zeit (Mittel)':>14}{'ggü. Bonus aus: Mittel':>24}"
              f"{'P90':>9}{'Max':>9}{'ggü. 2.1':>11}")
        for b in ("aus", "Start", FINAL, "Stress x4"):
            tt = [st.times(p) for p in batches[b]]
            for m in MS[2:]:
                vals = [x[m] for x in tt]
                red = [(y[m] - x[m]) / y[m] for x, y in zip(tt, tb)]
                mean_t = sum(vals) / len(vals)
                vs_ref = (ref[m] - mean_t) / ref[m] if ref else float("nan")
                print(f"  {b:<11}{st.MILESTONE_LABEL[m]:<14}{st.fmt_t(mean_t):>14}"
                      f"{fmt_pct(sum(red) / len(red)):>24}{fmt_pct(pct(red, 0.9)):>9}{fmt_pct(max(red)):>9}"
                      f"{(fmt_pct(vs_ref) if ref else '-'):>11}")
                summary[(vname, b, m)] = (mean_t, sum(red) / len(red), pct(red, 0.9), max(red))
        # Sammlung am Ende des ersten Laufs (Final)
        ps = batches[FINAL]
        finds = [p.finds for p in ps]
        newf = [p.new_finds for p in ps]
        nsets = [len(p.sets_done) for p in ps]
        bonus_end = [p.bonus_bp for p in ps]
        print(f"  Funde im ersten Lauf: Mittel {sum(finds) / len(finds):.1f}, davon neu {sum(newf) / len(newf):.1f}; "
              f"fertige Sets: Mittel {sum(nsets) / len(nsets):.2f}, P90 {pct(nsets, 0.9)}, max {max(nsets)}; "
              f"mind. 1 Set: {fmt_pct(sum(1 for n in nsets if n) / len(nsets))}; "
              f"Bonus am Ende (Final) Mittel {sum(bonus_end) / len(bonus_end) / 100:.2f} %, max {max(bonus_end) / 100:.0f} %")
        per_zone = {}
        for p in ps:
            for (z, si) in p.sets_done:
                per_zone[(z, si)] = per_zone.get((z, si), 0) + 1
        if per_zone:
            print("  Anteil der Läufe mit fertigem Set: " + ", ".join(
                f"{ZONE_NAME[z]} S{si + 1} {fmt_pct(n / len(ps))}" for (z, si), n in sorted(per_zone.items())))
        gz = {}
        for p in ps:
            for z, g in p.gather_by_zone.items():
                gz[z] = gz.get(z, 0) + g / len(ps)
        lg = sum(p.luck_gather for p in ps) / sum(p.cum_gather for p in ps)
        print("  Sammelzeit je Zone (Mittel): " + ", ".join(f"{ZONE_NAME[z]} {fmt_dur(g)}" for z, g in gz.items())
              + f"; Glück im Mittel der Sammelzeit x{lg:.2f}")
        # Duplikat-Anteil je Werkzeug
        line = []
        for tool in st.PHASES:
            d = sum(p.dupe_coins.get(tool, 0) for p in ps)
            s = sum(p.sand_coins.get(tool, 0) for p in ps)
            if s:
                line.append(f"{st.TOOL_NAME[tool]} {fmt_pct(d / (d + s))}")
        print("  Anteil Duplikat-Münzen je Werkzeug (echt, Final): " + ", ".join(line))
        summary[(vname, "gather")] = gz
        summary[(vname, "luck")] = lg
        summary[(vname, "play")] = sum(p.t for p in ps) / len(ps)
        summary[(vname, "gatherall")] = sum(p.cum_gather for p in ps) / len(ps)

    print("\n  Obere Schranke (deterministisch): Set 1 jeder Zone fertig, sobald der Spieler sie betritt")
    for b in ("Start", FINAL, "Stress x4"):
        for label, nodes, ref in (("Tore", None, ref_g), ("ohne Tore", st.NODES_NO_GATES, ref_n)):
            tw = st.times(worst_case_run([0], BONUS[b], nodes=nodes))
            print(f"  {b:<10} {label:<10}" + ", ".join(
                f"{st.MILESTONE_LABEL[m]} {st.fmt_t(tw[m])} ({fmt_pct((ref[m] - tw[m]) / ref[m])})" for m in MS[2:]))
    for b in ("Start", FINAL):
        tw = st.times(worst_case_run([0, 1], BONUS[b]))
        print(f"  {b:<10} Tore, Set 1+2 je Zone: " + ", ".join(
            f"{st.MILESTONE_LABEL[m]} {st.fmt_t(tw[m])} ({fmt_pct((ref_g[m] - tw[m]) / ref_g[m])})" for m in MS[2:]))

    # ---------------------------------------------------------------- 4. Duplikat-Anteil (Methode 2.1)
    section("4. Anteil der Münzen aus Funden, wenn jeder Fund verkauft wird (Methode 2.1, Knoten zu Phasenbeginn)")
    ev = sum(ODDS[r] * VALUE[r] for r in RARITY)
    print(f"  Erwartungswert Wertfaktor je Fund x{ev:.3f}")
    p0 = st.simulate(buy_luck=True)
    for b_label, bp in (("ohne Bonus", 0), ("+25 % (ein Buch Start)", 2500), ("+34 % (ein Buch Final)", 3400),
                        ("+125 % (5 Bücher Start)", 12500), ("+170 % (5 Bücher Final)", 17000)):
        sim = st.Player(buy_luck=True, find_coins=True)
        parts = []
        for t, i, _, _ in p0.log:
            n = sim.node[i]
            sim.owned.add(i)
            if n[6] == "setTool":
                g = sim.capacity / sim.rate
                f = g * sim.find_coins_per_gather_s()
                s = sim.capacity * sim.price * (10000 + bp) / 10000
                parts.append(f"{st.TOOL_NAME[sim.tool]} {fmt_pct(f / (f + s))}")
        print(f"  {b_label:<26}" + ", ".join(parts))
    # Ruinenstadt nach dem Sandsturm mit der Hand (phase0: 39 %)
    for b_label, bp in (("ohne Bonus", 0), ("+34 %", 3400), ("+170 %", 17000)):
        g = 15 / 1
        f = g * FIND_CHANCE * ZONE_FACTOR["ruins"] * FIND_BASE_VALUE * SAND_FACTOR["ruins"] * 1 * ev
        s = 15 * SAND_FACTOR["ruins"] * (10000 + bp) / 10000
        print(f"  Ruinenstadt, Hand, ohne Knoten, {b_label:<10}: {fmt_pct(f / (f + s))}")

    # ---------------------------------------------------------------- 5. Sandsturm-Rhythmus
    section("5. Sandsturm-Rhythmus: wann sieht ein Spieler Set 6?")
    v = "Tore, Entwurf"
    play = summary[(v, "play")]
    gather_all = summary[(v, "gatherall")]
    frac = gather_all / play
    luck_avg = summary[(v, "luck")]
    print(f"  Erster Lauf: Spielzeit {fmt_dur(play)}, Sammelzeit {fmt_dur(gather_all)} ({fmt_pct(frac, 0)}), "
          f"Glück im Mittel x{luck_avg:.2f}")
    print(f"  Annahmen: nach jedem Sturm gleich lange Läufe, alles in der Ruinenstadt (Sandfaktor 150 schlägt alle"
          f" anderen), Glück-Ast wird je Lauf neu gekauft (Mittel x{luck_avg:.2f}), {PLAY_MIN_PER_DAY:.0f} min Spiel pro Tag.")
    for lay_name in ("Entwurf", "V1 (Set 1 = 5c)"):
        print(f"\n  {lay_name}: Ruinenstadt, Sammelzeit / Spielzeit / Läufe / Tage (Mittel; P90 in Klammern)")
        rows = analytic_table(LAYOUTS[lay_name], lam_of("ruins", luck_avg))
        for i, (m, q) in enumerate(rows):
            lab = f"Set {i + 1}" if i < 6 else "Zonenbuch"
            pm, pq = m / frac, q / frac
            print(f"    {lab:<10} {fmt_dur(m):>11} ({fmt_dur(q)})  Spiel {fmt_dur(pm):>11} ({fmt_dur(pq)})"
                  f"  Läufe {pm / play:5.1f} ({pq / play:5.1f})  Tage {pm / 60 / PLAY_MIN_PER_DAY:5.1f}"
                  f" ({pq / 60 / PLAY_MIN_PER_DAY:5.1f})")
    print("\n  Dünenmeer: Sammelzeit dort fällt nur im ersten Lauf an (danach ist die Ruinenstadt besser).")
    g_d = summary[(v, "gather")]["dunes"]
    rates = set_rates(LAYOUTS["Entwurf"], lam_of("dunes", 1.05))
    print(f"  Sammelzeit Dünenmeer im ersten Lauf {fmt_dur(g_d)}: " + ", ".join(
        f"P(Set {i + 1}) {fmt_pct(cdf_max(r, g_d), 2)}" for i, r in enumerate(rates)))
    print("  Wer das Dünenbuch gezielt sammelt (voller Glück-Ast x2): "
          f"{fmt_dur(analytic_table(LAYOUTS['Entwurf'], lam_of('dunes', 2.0))[6][0])} Sammelzeit, "
          f"Ertrag dort 1/150 der Ruinenstadt.")
    total = sum(analytic_table(LAYOUTS["Entwurf"], lam_of(z, 2.0))[6][0] for z in ZONES)
    print(f"  Alle fünf Zonenbücher mit Glück x2 nacheinander: {fmt_dur(total)} Sammelzeit, "
          f"etwa {total / frac / 60 / PLAY_MIN_PER_DAY:.0f} Tage bei {PLAY_MIN_PER_DAY:.0f} min pro Tag")

    # ---------------------------------------------------------------- 6. Ausnutzung und Nebenwerte
    section("6. Ausnutzungswege und Nebenwerte")
    for z in ("oasis", "canyon", "salt_lake"):
        print(f"  Fundrate {ZONE_NAME[z]:<9} mit Glück x2: {FIND_CHANCE * ZONE_FACTOR[z] * 2:.4f}/s"
              + (f", im Regen {FIND_CHANCE * ZONE_FACTOR[z] * 2 * 1.15:.4f}/s" if z == "oasis" else ""))
    rain_only = analytic_table(LAYOUTS["Entwurf"], FIND_CHANCE * 1.2 * 2 * 1.15)
    any_time = analytic_table(LAYOUTS["Entwurf"], lam_of("oasis", 2.0))
    print(f"  Oasenbuch nur im Regen gesammelt: {fmt_dur(rain_only[6][0])} Sammelzeit statt {fmt_dur(any_time[6][0])}"
          f" ({fmt_pct(1 - rain_only[6][0] / any_time[6][0])} weniger), braucht aber {RAIN['cycle'] / RAIN['active']:.1f}x so viel Wanduhrzeit")
    # Ein Wurf pro Verkauf statt pro Tick
    for z, luck in (("dunes", 1.0), ("salt_lake", 2.0), ("ruins", 2.0)):
        p = FIND_CHANCE * ZONE_FACTOR[z] * luck
        for g in (20, 30):
            one = 1 - (1 - p) ** g
            print(f"  Ein Wurf je {g}-s-Fenster statt je Tick, {ZONE_NAME[z]:<11} Glück x{luck:.0f}: "
                  f"{one:.3f} statt {p * g:.3f} Funde ({fmt_pct(1 - one / (p * g))} weniger)")
    # Offline: Begleiter ohne Funde ab Selten
    for hours in (4, 12):
        n = hours * 3600 * FIND_CHANCE
        q = set_rates(LAYOUTS["Entwurf"], FIND_CHANCE)[0]
        print(f"  Offline {hours:>2} h Dünenmeer bei voller Fundchance: {n:.0f} Funde, "
              f"P(Set 1 Entwurf fertig) {fmt_pct(cdf_max(q, hours * 3600), 2)}"
              f" (Set 1 enthält nur Gewöhnlich und Ungewöhnlich)")
    # Goldkiste Legendär oder besser (Kontrolle, unverändert)
    p_l = 0.045 + 0.005
    e_open = (1 - (1 - p_l) ** 60) / p_l
    print(f"  Kontrolle Goldkiste: Legendär oder besser im Mittel nach {e_open:.2f} Öffnungen, "
          f"{e_open * 400:,.0f} Gems einzeln, {e_open * 400 * 10 / 11:,.0f} Gems im 10er-Paket".replace(",", "."))
    # Erster Legendär-oder-besser-Fund
    for z in ("dunes", "ruins"):
        for luck in (1.0, 2.0):
            lam = lam_of(z, luck) * (ODDS["l"] + ODDS["m"])
            print(f"  Erster Legendär-oder-besser-Fund {ZONE_NAME[z]:<11} Glück x{luck:.0f}: "
                  f"Mittel {fmt_dur(1 / lam)}, P90 {fmt_dur(math.log(10) / lam)} Sammelzeit")


if __name__ == "__main__":
    main()
