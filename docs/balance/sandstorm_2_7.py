#!/usr/bin/env python3
"""Dune Baron, Paket 2.7: Sandsturm (Prestige) mit Windkristallen.

Fragen (Bericht: docs/balance/sandstorm_2_7.md):
  1. crystalUnit, crystalExponent, crystalScale, maxCrystals und der Preis von sandstorm_ruins.
  2. Lauf 1 bis 10 je Sturm-Strategie: Laufdauer, Kristalle, Gesamtbonus, Münzen/s, Spieltage.
  3. Engpässe und Fallen (früher Sturm, Sturm am Baumende, 2x Münzen, Auto-Dig), minCrystals.

Formel (entschieden): Kristalle = floor(scale * (runEarned / unit) ^ exponent), höchstens maxCrystals.
runEarned = Münzen aus Sandverkäufen und verkauften Duplikaten seit dem letzten Sturm.
Jeder Kristall gibt +2 % (Economy.windCrystalBonusBp = 200) auf Sandpreis und Fundwert,
multipliziert mit Verkauf-Ast und Sammlungsbonus.

Der Sturm setzt Münzen, Tank, alle gekauften Knoten, Werkzeug und Zonen zurück. sandstorm_1
bleibt, Sammlung (Funde und Set-Bonus) bleibt. sandstorm_ruins (requires sandstorm_1 und
collect_tool_5) wird jeden Lauf neu gekauft und schaltet die Ruinenstadt (Sandfaktor 150,
Fundfaktor 2,0) frei.

Schleife, Baum und Kaufregel aus skilltree_2_1.py (billigster sichtbarer Knoten, Glück-Ast wird
mitgekauft, 5 s Weg je Richtung, beste freigeschaltete Zone), Funde, Duplikate und Sammlung aus
collection_2_6.py (Layout V1 wie in Finds.luau, Set-Bonus Final wie in Collection.luau).
Baum: heutiger Stand ohne Tore (UpgradeTree.luau), mit Toren nur als Gegenprobe für Paket 6.4.

Nur Standardbibliothek, feste Seeds. Aufruf: python3 docs/balance/sandstorm_2_7.py
"""

import copy
import math
import os
import random
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import collection_2_6 as col  # noqa: E402
st = col.st

# ---------------------------------------------------------------------------
# Daten und Vorschlag
# ---------------------------------------------------------------------------

CRYSTAL_BONUS_BP = 200                  # Economy.windCrystalBonusBp
PLAY_MIN_PER_DAY = 15.0                 # Annahme wie in 2.6
SEED = 2700

# Vorschlag (Ergebnis der Suche in Abschnitt 1)
FORMULA = dict(unit=1e6, exponent=0.25, scale=4.0, cap=100_000)
RUINS_COST = 250_000_000
MIN_CRYSTALS = 20

ZONES5 = st.ZONES + [("ruins", 150, "sandstorm_ruins", 2.0)]


def ruins_node(cost):
    return ("sandstorm_ruins", "Ruinenkarte", "Schaltet die Ruinenstadt frei", "sandstorm",
            ["sandstorm_1", "collect_tool_5"], cost, "unlockZone", "ruins")


def tree(ruins_cost=RUINS_COST, gates=False):
    base = list(st.NODES if gates else st.NODES_NO_GATES)
    return base + ([ruins_node(ruins_cost)] if ruins_cost is not None else [])


def crystals(earned, f=None):
    f = f or FORMULA
    if earned < f["unit"]:
        return 0
    return min(f["cap"], math.floor(f["scale"] * (earned / f["unit"]) ** f["exponent"]))


# ---------------------------------------------------------------------------
# Spieler mit Kristallen, Sammlung und Ruinenstadt
# ---------------------------------------------------------------------------

class StormPlayer(col.FindPlayer):
    def __init__(self, rng, state, nodes, coin_mult=1.0, autodig=False, earned_raw=False):
        super().__init__(rng, col.LAYOUTS["V1 (Set 1 = 5c)"], col.BONUS[col.FINAL],
                         nodes=nodes, coin_mult=coin_mult, autodig=autodig)
        # sandstorm_1 wird vergeben, nie gekauft: nur im Nachschlag, nicht in der Kaufliste
        self.node["sandstorm_1"] = ("sandstorm_1", "Der erste Sturm", "", "sandstorm", [], 0,
                                    "grantedBySandstorm", None)
        self.owned = set(state["granted"])
        self.found = state["found"]
        self.bonus_bp = state["bonus_bp"]
        self.sets_done = state["sets_done"]
        self.crystals = state["crystals"]
        self.earned_raw = earned_raw      # Variante: runEarned ohne 2x Münzen
        self.run_earned = 0.0
        self.trips = []                   # (t, runEarned, Münzen/s des Laufs)

    @property
    def zone(self):
        best = ZONES5[0]
        for z in ZONES5:
            if z[2] is None or z[2] in self.owned:
                if z[0] != "ruins" or "sandstorm_1" in self.owned:
                    best = z
        return best

    @property
    def mult(self):
        return (10000 + self.crystals * CRYSTAL_BONUS_BP) / 10000

    @property
    def price(self):
        return col.FindPlayer.price.fget(self) * self.mult

    def _find(self, zone, rarity, t):
        return super()._find(zone, rarity, t) * self.mult

    def run(self):
        cap, rate = self.capacity, self.rate
        start = min(cap, rate * st.WALK_ONE_WAY_S) if (self.autodig and self.runs) else 0.0
        gather = (cap - start) / rate
        zone, tool = self.zone[0], self.tool
        find_coins = self._gather_finds(zone, self.t - start / rate, gather + start / rate)
        self.t += gather + st.WALK_ONE_WAY_S
        sand = cap * self.price
        earned = sand + find_coins
        self.coins += earned
        self.run_earned += (sand / self.coin_mult if self.earned_raw else sand) + find_coins
        run_len = gather + 2 * st.WALK_ONE_WAY_S
        self.runs.append((self.t, tool, zone, gather, run_len, earned))
        self.trips.append((self.t, self.run_earned, earned / run_len))
        self.buy(earned / run_len)
        self.t += st.WALK_ONE_WAY_S


def new_state():
    return dict(granted=set(), found={}, bonus_bp=0, sets_done={}, crystals=0, history=[])


# Strategien: Funktion (Spieler, Kristalle jetzt) -> stürmen?
def s_threshold(x):
    return lambda p, c: c >= x


def s_tree_end(p, c):
    return p.done() and c >= 1


MAX_RUN_S = 6 * 3600


def play_run(state, nodes, strategy, seed, f=None, min_c=1, stop_trip=None, **kw):
    """Ein Lauf bis zum Sturm. stop_trip: Sturm genau nach diesem Gang (für die Optimum-Suche)."""
    rng = random.Random(seed)
    p = StormPlayer(rng, state, nodes, **kw)
    k = 0
    while p.t < MAX_RUN_S:
        p.run()
        k += 1
        c = crystals(p.run_earned, f)
        allowed = "collect_tool_4" in p.owned and c >= max(1, min_c)
        if stop_trip is not None:
            if k >= stop_trip:
                break
        elif allowed and strategy(p, c):
            break
    p.end_t = max((t for t, _, _, _ in p.log), default=None) if p.done() else None
    return p


def best_trip(state, nodes, seed, f=None, horizon_after_end=1800, **kw):
    """Gang mit der höchsten Kristallrate (Kristalle / Laufdauer) für diesen einen Lauf."""
    probe_state = copy.deepcopy(state)
    rng = random.Random(seed)
    p = StormPlayer(rng, probe_state, nodes, **kw)
    end_t, best, k = None, (0.0, None), 0
    while p.t < MAX_RUN_S:
        p.run()
        k += 1
        if end_t is None and p.done():
            end_t = p.t
        c = crystals(p.run_earned, f)
        if "collect_tool_4" in p.owned and c >= 1:
            r = c / p.t
            if r > best[0]:
                best = (r, k)
        if end_t is not None and p.t > end_t + horizon_after_end:
            break
    return best[1]


def campaign(strategy, runs=10, nodes=None, f=None, min_c=1, optimal=False, **kw):
    nodes = nodes or tree()
    state = new_state()
    out = []
    total_t = 0.0
    for r in range(runs):
        seed = SEED + r
        if optimal:
            k = best_trip(state, nodes, seed, f=f, **kw)
            p = play_run(state, nodes, None, seed, f=f, stop_trip=k, **kw)
        else:
            p = play_run(state, nodes, strategy, seed, f=f, min_c=min_c, **kw)
        c = crystals(p.run_earned, f)
        times = st.times(p)
        total_t += p.t
        last = p.trips[-1][2]
        out.append(dict(run=r + 1, t=p.t, c=c, total_c=state["crystals"] + c, mult_in=p.mult,
                        earned=p.run_earned, cps=p.run_earned / p.t, cps_end=last,
                        tree_done=p.done(), times=times, days=total_t / 60 / PLAY_MIN_PER_DAY,
                        coll_bp=state["bonus_bp"], log=p.log))
        state["crystals"] += c
        state["granted"].add("sandstorm_1")
        state["bonus_bp"] = p.bonus_bp
    return out


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

def fmt_t(s):
    if s is None:
        return "-"
    s = int(round(s))
    if s >= 3600:
        return f"{s // 3600}:{s % 3600 // 60:02d} h"
    return f"{s // 60}:{s % 60:02d}"


fmt_n = st.fmt_n


def section(title):
    print()
    print("=" * 100)
    print(title)
    print("=" * 100)


def print_campaign(name, res):
    print(f"\n  --- {name} ---")
    print(f"  {'Lauf':>4} {'Dauer':>8} {'Baum':>5} {'runEarned':>14} {'Kristalle':>9} {'Summe':>6}"
          f" {'Bonus':>7} {'Münzen/s Mittel':>16} {'Münzen/s Ende':>14} {'Tage':>6} {'Ruinen':>7}")
    for x in res:
        ruins = x["times"].get("sandstorm_ruins")
        print(f"  {x['run']:>4} {fmt_t(x['t']):>8} {'ja' if x['tree_done'] else 'nein':>5}"
              f" {fmt_n(x['earned']):>14} {x['c']:>9} {x['total_c']:>6}"
              f" {x['total_c'] * CRYSTAL_BONUS_BP / 100:>6.0f}%"
              f" {fmt_n(x['cps']):>16} {fmt_n(x['cps_end']):>14} {x['days']:>6.1f} {fmt_t(ruins):>7}")


def summary_line(name, res):
    t = sum(x["t"] for x in res)
    print(f"  {name:<34} Summe {fmt_t(t):>8} ({t / 60 / PLAY_MIN_PER_DAY:5.1f} Tage), Kristalle"
          f" {res[-1]['total_c']:>6} (Bonus {res[-1]['total_c'] * 2:>5} %), Lauf 2 {fmt_t(res[1]['t'])},"
          f" Lauf 10 {fmt_t(res[-1]['t'])}, Kristalle/h {res[-1]['total_c'] / (t / 3600):7.1f}")


START = dict(unit=1e6, exponent=0.5, scale=1.0, cap=1_000_000)   # Startvorschlag aus dem Auftrag
START_RUINS = 500_000_000                                         # Platzhalter in UpgradeTree.luau


def crystals_at_budget(res, minutes):
    t, c = 0.0, 0
    for x in res:
        t += x["t"]
        if t > minutes * 60:
            break
        c = x["total_c"]
    return c


def main():
    nodes = tree()

    # ------------------------------------------------------------ 0. Erster Lauf als Referenz
    section("0. Erster Lauf (heutiger Baum ohne Tore, mit Glück-Ast): runEarned und Kristalle")
    q = StormPlayer(random.Random(SEED), new_state(), nodes)
    marks = {}
    while not q.done():
        q.run()
        for _t, i, _c, _inc in q.log:
            marks.setdefault(i, (q.t, q.run_earned))
    forms = (("Start 1 Mio./0,5/1", START), ("Vorschlag 1 Mio./0,25/4", FORMULA),
             ("1 Mio./0,4/1", dict(unit=1e6, exponent=0.4, scale=1, cap=10**6)))
    print(f"  {'Punkt':<14} {'Zeit':>7} {'runEarned':>12}" + "".join(f"{n:>26}" for n, _ in forms))
    for i, lab in (("collect_tool_4", "Mini-Bagger"), ("collect_tool_5", "Saugroboter"),
                   ("collect_tool_6", "Großmaschine"), ("luck_6", "luck_6"), ("sell_8", "sell_8"),
                   ("collect_rate_12", "Baumende")):
        t, e = marks[i]
        print(f"  {lab:<14} {fmt_t(t):>7} {fmt_n(e):>12}" + "".join(f"{crystals(e, f):>26}" for _, f in forms))
    print(f"  Ertrag am Baumende {fmt_n(q.trips[-1][2])} Münzen/s, danach kein Knoten mehr (Einkommen stockt).")
    need = FORMULA["unit"] * (MIN_CRYSTALS / FORMULA["scale"]) ** (1 / FORMULA["exponent"])
    t_min = next(t for t, e, _ in q.trips if e >= need)
    print(f"  minCrystals {MIN_CRYSTALS} braucht runEarned {fmt_n(need)}, erreicht im ersten Lauf bei {fmt_t(t_min)}.")

    # ------------------------------------------------------------ 1. Formel-Suche
    section("1. Formel-Suche: Sturm am Baumende, kristallraten-optimal, Kristalle nach 45/90/180 min Spiel")
    cands = [(1e6, 0.5, 1), (1e7, 0.5, 1), (1e6, 0.4, 1), (1e6, 0.3, 3), (1e6, 0.25, 4), (1e6, 0.25, 5),
             (1e6, 0.2, 6)]
    for u, e, sc in cands:
        f = dict(unit=u, exponent=e, scale=sc, cap=10**6)
        a = campaign(s_tree_end, f=f, runs=40)
        b = campaign(None, f=f, optimal=True, runs=25)
        t10 = campaign(s_threshold(10), f=f, runs=40)
        t20 = campaign(s_threshold(20), f=f, runs=40)
        end1 = a[0]["t"]
        under5 = next((x["run"] for x in a if x["t"] < 300), None)
        bud = lambda r: "/".join(str(crystals_at_budget(r, m)) for m in (45, 90, 180))
        print(f"  u {fmt_n(u):>8} e {e:.2f} s {sc}: Baumende L1 {a[0]['c']:>3} Kr., L2 {fmt_t(a[1]['t'])}"
              f" ({a[1]['t'] / a[0]['t']:.0%}), L10 {fmt_t(a[9]['t'])}, erster Lauf < 5 min: {under5},"
              f" optimal L1 {fmt_t(b[0]['t'])} (+{(b[0]['t'] - end1) / 60:.1f} min)")
        print(f"  {'':>24} nach 45/90/180 min: Schwelle 10 {bud(t10)}, Schwelle 20 {bud(t20)},"
              f" Baumende {bud(a)}, optimal {bud(b)}")

    # ------------------------------------------------------------ 2. Preis der Ruinenkarte
    l1 = campaign(s_tree_end, runs=1)[0]["c"]
    section(f"2. Preis von sandstorm_ruins (Lauf 2 mit {l1} Kristallen aus Lauf 1, Sturm am Baumende)")
    print(f"  {'Preis':>10} {'gekauft':>8} {'nach':>16} {'kostet':>9} {'Großm.':>7} {'Baumende':>9}"
          f" {'ohne Karte':>11} {'Diff':>6}")
    s0 = new_state()
    s0["granted"].add("sandstorm_1")
    s0["crystals"] = l1
    for gates in (False, True):
        if gates:
            print("  Gegenprobe mit Toren (Ziel von Paket 6.4):")
        ref = play_run(copy.deepcopy(s0), tree(None, gates=gates), s_tree_end, SEED + 1)
        for cost in ((2e6, 25e6, 100e6, 150e6, 250e6, 300e6, 500e6, 1e9) if not gates else (100e6, 250e6, 500e6)):
            pr = play_run(copy.deepcopy(s0), tree(cost, gates=gates), s_tree_end, SEED + 1)
            ent = [x for x in pr.log if x[1] == "sandstorm_ruins"][0]
            prev = [i for t, i, _, _ in pr.log if t <= ent[0] and i != "sandstorm_ruins"][-1]
            tg = [t for t, i, _, _ in pr.log if i == "collect_tool_6"][0]
            print(f"  {fmt_n(cost):>10} {fmt_t(ent[0]):>8} {prev:>16} {ent[2] / ent[3]:>7.0f} s"
                  f" {fmt_t(tg):>7} {fmt_t(pr.end_t):>9} {fmt_t(ref.end_t):>11} {pr.end_t - ref.end_t:>+5.0f}s")

    # ------------------------------------------------------------ 3. Strategien mit dem Vorschlag
    section(f"3. Läufe 1 bis 10 mit dem Vorschlag {FORMULA}, Ruinenkarte {fmt_n(RUINS_COST)}")
    strategies = [
        ("früh: erster Kristall (4)", dict(strategy=s_threshold(1))),
        ("Schwelle 10", dict(strategy=s_threshold(10))),
        (f"Schwelle {MIN_CRYSTALS} (= minCrystals)", dict(strategy=s_threshold(MIN_CRYSTALS))),
        ("Baumende", dict(strategy=s_tree_end)),
        ("kristallraten-optimal", dict(strategy=None, optimal=True)),
    ]
    results = {}
    for name, kw in strategies:
        results[name] = campaign(**kw)
        print_campaign(name, results[name])
    print()
    for name, _ in strategies:
        summary_line(name, results[name])
    print("\n  Startvorschlag zum Vergleich (1 Mio./0,5/1, Ruinenkarte 500 Mio.):")
    sv_nodes = tree(START_RUINS)
    sv_end = campaign(s_tree_end, f=START, nodes=sv_nodes)
    sv_opt = campaign(None, f=START, nodes=sv_nodes, optimal=True)
    print_campaign("Start, Baumende", sv_end)
    print_campaign("Start, kristallraten-optimal", sv_opt)
    summary_line("Start, Baumende", sv_end)
    summary_line("Start, kristallraten-optimal", sv_opt)

    # ------------------------------------------------------------ 4. Gamepässe
    section("4. 2x Münzen und Auto-Dig (Sturm am Baumende und kristallraten-optimal)")
    for name, kw in (("ohne Pass", {}), ("2x Münzen", dict(coin_mult=2.0)),
                     ("2x Münzen, runEarned ohne Pass", dict(coin_mult=2.0, earned_raw=True)),
                     ("Auto-Dig (obere Schranke)", dict(autodig=True))):
        summary_line(name + ", Baumende", campaign(s_tree_end, **kw))
        summary_line(name + ", optimal", campaign(None, optimal=True, **kw))
    for f_name, f in (("Start", START), ("Vorschlag", FORMULA)):
        a = campaign(s_tree_end, f=f, runs=1)[0]["c"]
        b = campaign(s_tree_end, f=f, runs=1, coin_mult=2.0)[0]["c"]
        print(f"  {f_name}: Kristalle am Baumende Lauf 1 ohne Pass {a}, mit 2x Münzen {b} (x{b / a:.2f})")

    # ------------------------------------------------------------ 5. Früh oder spät im Lauf 1
    section("5. Lauf 1: Sturm an verschiedenen Punkten, danach Lauf 2 bis Baumende")
    print(f"  Sturm direkt nach collect_tool_4: runEarned {fmt_n(marks['collect_tool_4'][1])} ->"
          f" {crystals(marks['collect_tool_4'][1])} Kristalle, Antwort tooFew")
    end_t = marks["collect_rate_12"][0]
    for name, strat in (("erster Kristall", s_threshold(1)), ("10 Kristalle", s_threshold(10)),
                        (f"{MIN_CRYSTALS} Kristalle", s_threshold(MIN_CRYSTALS)), ("Baumende", s_tree_end),
                        ("Baumende + 5 min", lambda p, c: p.t >= end_t + 300),
                        ("Baumende + 15 min", lambda p, c: p.t >= end_t + 900)):
        s = new_state()
        p1 = play_run(s, nodes, strat, SEED)
        c1 = crystals(p1.run_earned)
        s["crystals"] = c1
        s["granted"].add("sandstorm_1")
        p2 = play_run(s, nodes, s_tree_end, SEED + 1)
        c2 = c1 + crystals(p2.run_earned)
        print(f"  {name:<18} Lauf 1 {fmt_t(p1.t):>7}, {c1:>3} Kristalle (+{c1 * 2:>3} %),"
              f" Lauf 2 {fmt_t(p2.t):>7}, zusammen {fmt_t(p1.t + p2.t):>7}, {c2:>3} Kristalle,"
              f" {c2 / ((p1.t + p2.t) / 60):.2f} Kristalle/min")

    # ------------------------------------------------------------ 6. Kontrollen
    section("6. Kontrollen")
    for e in (1e3, 1e6, 1e9, 1e12, 1e15, 1e18, 1e24, 1e300):
        print(f"  runEarned {e:>8.0e} -> {crystals(e):>9} Kristalle")
    cap_at = FORMULA["unit"] * (FORMULA["cap"] / FORMULA["scale"]) ** (1 / FORMULA["exponent"])
    print(f"  Obergrenze {fmt_n(FORMULA['cap'])} Kristalle je Sturm (+{fmt_n(FORMULA['cap'] * 2)} %),"
          f" erreicht bei runEarned {cap_at:.1e}")
    res = results["Baumende"]
    for x in res[:4]:
        t = x["times"]
        gaps, prev = [], 0.0
        for tt, i, _, _ in x["log"]:
            gaps.append((tt - prev, i))
            prev = tt
        g = max(gaps)
        print(f"  Lauf {x['run']}: Upgrade 1 {fmt_t(t.get('collect_rate_1'))}, Schaufel {fmt_t(t.get('collect_tool_2'))},"
              f" Eimerkette {fmt_t(t.get('collect_tool_3'))}, Mini-Bagger {fmt_t(t.get('collect_tool_4'))},"
              f" Großmaschine {fmt_t(t.get('collect_tool_6'))}, Ruinen {fmt_t(t.get('sandstorm_ruins'))},"
              f" Baumende {fmt_t(max(tt for tt, _, _, _ in x['log']))}, längste Pause {g[0]:.0f} s vor {g[1]},"
              f" Sammlung {x['coll_bp'] / 100:.0f} %")
    g = campaign(s_tree_end, nodes=tree(gates=True))
    summary_line("Gegenprobe mit Toren, Baumende", g)
    print(f"  Gegenprobe mit Toren: Lauf 1 {fmt_t(g[0]['t'])} {g[0]['c']} Kristalle, Lauf 2 {fmt_t(g[1]['t'])}")
    p_l = 0.045 + 0.005
    e_open = (1 - (1 - p_l) ** 60) / p_l
    print(f"  Goldkiste unverändert: Legendär oder besser im Mittel nach {e_open:.1f} Öffnungen ="
          f" {e_open * 400:,.0f} Gems".replace(",", "."))


if __name__ == "__main__":
    main()
