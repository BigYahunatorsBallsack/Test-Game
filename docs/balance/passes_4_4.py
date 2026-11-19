#!/usr/bin/env python3
"""Dune Baron, Paket 4.4: Gamepässe (2x Münzen, Großer Tank, Auto-Dig) und Münz-Boost.

Bewertet die freigegebenen Regeln, ändert nichts. Bericht: docs/balance/passes_4_4.md.

Fragen
  1. 2x-Pass, Boost und beide zusammen: Zeit bis zum Baumende in Lauf 1, Zeit je Sturm-Lauf,
     Kristalle je Lauf, über 10 Läufe und nach fester Spielzeit (Zinseszins über den Windbonus).
  2. Großer Tank: gesparte Wegzeit je Zone, Wirkung über den ganzen Baum, Abhängigkeit vom Weg.
  3. Auto-Dig: Mehrertrag gegenüber manuellem Halten, AFK-Wert.
  4. x4 (Pass x Boost) gegen additiv x3: Holzkiste, Sturm-Schwelle, Lauflängen.

Modell: Baum, Schleife und Kaufregel aus skilltree_2_1.py, Funde und Sammlung aus collection_2_6.py,
Kristalle, Ruinenkarte und Sturm aus sandstorm_2_7.py (alles importiert, nichts kopiert).
Der Münzfaktor (Pass, Boost) wirkt auf Sandverkauf und verkaufte Duplikate und damit auf runEarned.
Der Boost läuft in echter Zeit, das Skript rechnet mit einer globalen Spieluhr über alle Läufe.

Nur Standardbibliothek, feste Seeds ab 4400. Aufruf: python3 docs/balance/passes_4_4.py (etwa 3 s).
"""

import math
import os
import random
import re
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sandstorm_2_7 as ss  # noqa: E402

col = ss.col
st = ss.st
ROOT = os.path.dirname(os.path.dirname(HERE))

SEED = 4400
MIN_CRYSTALS = 20                 # Economy.sandstorm.minCrystals
WOOD_CRATE = 25_000               # Crates.luau / Konzept: Holzkiste
WOOD_CAP_COST = 81_000_000        # Holz-Deckel (+44,8 %) aus equipment_4_3.md
BOOST_S = 30 * 60                 # Economy.coinBoost.durationSeconds
PRICE = {"double_coins": 399, "big_tank": 199, "auto_dig": 499, "coin_boost": 49}


# ---------------------------------------------------------------------------
# 0. Abgleich mit den Datenmodulen (liest die .luau-Dateien, damit das Modell nicht veraltet)
# ---------------------------------------------------------------------------

def luau(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def check_data():
    eco = luau("src/shared/Data/Economy.luau")
    tree = luau("src/shared/Data/UpgradeTree.luau")
    tools = luau("src/shared/Data/Tools.luau")
    out = []
    num = lambda pat, txt: float(re.search(pat, txt, re.S).group(1).replace("_", ""))
    found = {
        "bigTankMultiplier": num(r"bigTankMultiplier\s*=\s*([\d_.]+)", eco),
        "coinBoost.multiplier": num(r"coinBoost\s*=\s*\{.*?multiplier\s*=\s*([\d_.]+)", eco),
        "coinBoost.durationSeconds": eval(re.search(r"durationSeconds\s*=\s*([\d *]+),", eco).group(1)),
        "startTankCapacity": num(r"startTankCapacity\s*=\s*([\d_]+)", eco),
        "windCrystalBonusBp": num(r"windCrystalBonusBp\s*=\s*([\d_]+)", eco),
    }
    m = re.search(r"doubleCoinsMultiplier\s*=\s*([\d_.]+)", eco)
    found["doubleCoinsMultiplier"] = float(m.group(1)) if m else None
    expect = {"bigTankMultiplier": st.BIG_TANK_MULTIPLIER, "coinBoost.multiplier": 2,
              "coinBoost.durationSeconds": BOOST_S, "startTankCapacity": st.START_TANK_CAPACITY,
              "windCrystalBonusBp": ss.CRYSTAL_BONUS_BP, "doubleCoinsMultiplier": 2}
    for k, v in expect.items():
        f = found[k]
        if f is None:
            out.append(f"  {k}: fehlt noch in Economy.luau (Modell nimmt {v})")
        elif abs(f - v) > 1e-9:
            out.append(f"  ABWEICHUNG {k}: Daten {f}, Modell {v}")
    costs = {}
    for blk in re.split(r"\n    \{", tree):
        i = re.search(r'id = "([a-z0-9_]+)"', blk)
        c = re.search(r"cost = ([\d_]+)", blk)
        if i and c:
            costs[i.group(1)] = int(c.group(1).replace("_", ""))
    model = {n[0]: n[5] for n in ss.tree()}
    diff = [k for k in model if k in costs and costs[k] != model[k]]
    missing = [k for k in model if k not in costs]
    out.append(f"  UpgradeTree.luau: {len(costs)} Knoten gelesen, Preisabweichungen zum Modell: "
               f"{diff or 'keine'}, im Modell aber nicht in den Daten: {missing or 'keine'}")
    rates = [int(x) for x in re.findall(r"sandPerSecond = (\d+)", tools)]
    out.append(f"  Tools.luau Raten {rates}, Modell {[t[2] for t in st.TOOLS]}")
    return out


# ---------------------------------------------------------------------------
# Spieler mit Münzfaktor nach Uhrzeit, Weg, Halten und Auto-Dig
# ---------------------------------------------------------------------------

def mult_const(m):
    return lambda t: m


def mult_boost(passes=1.0, boosts=1, boost_mult=2.0, combine="mul"):
    """Pass-Faktor dauerhaft, `boosts` Münz-Boosts direkt bei t = 0 gekauft (Zeit stapelt)."""
    end = boosts * BOOST_S

    def f(t):
        if t >= end:
            return passes
        return passes * boost_mult if combine == "mul" else passes + boost_mult - 1
    return f


class PassPlayer(ss.StormPlayer):
    """StormPlayer aus 2.7 mit Münzfaktor nach globaler Uhr, Weg, Halte-Anteil und Auto-Dig.

    hold:       Anteil der Feldzeit, in der der Spieler wirklich hält (1 = immer).
    hold_walk:  hält auch auf dem Rückweg vom Händler (der Server erlaubt Sammeln überall außer
                direkt am Stand, Sand.luau canCollect).
    autodig:    sammelt ohne Taste (hold = 1) auch auf dem Rückweg, stoppt bei vollem Tank.
    """

    def __init__(self, rng, state, nodes, schedule, t0=0.0, walk=5.0, hold=1.0, hold_walk=False,
                 autodig=False, big_tank=False, smart_sell=True):
        super().__init__(rng, state, nodes, coin_mult=1.0, autodig=autodig)
        self.smart_sell = smart_sell
        self.schedule = schedule
        self.t0 = t0
        self.walk = walk
        self.hold = 1.0 if autodig else hold
        self.hold_walk = hold_walk or autodig
        self.big_tank = big_tank
        self.first_wood = None        # Zeit, ab der der Lauf 25.000 Münzen verdient hat
        self.first_min = None         # Zeit, ab der der Sturm minCrystals bringt

    def _find(self, zone, rarity, t):
        # Duplikate werden verkauft: auch sie zählen mit dem Münzfaktor (Regel "aus allen Verkäufen")
        return super()._find(zone, rarity, t) * self.coin_mult

    def fill_target(self):
        """Füllmenge je Gang. Mit Großem Tank verkauft ein kluger Spieler schon, sobald der nächste
        Knoten bezahlbar ist, aber nie unter der normalen Tankgröße (er ist also nie langsamer als
        ohne Pass, solange der Weg gleich bleibt)."""
        cap = self.capacity
        if not (self.big_tank and self.smart_sell):
            return cap
        self.big_tank = False
        normal = self.capacity
        self.big_tank = True
        vis = self.visible()
        if not vis:
            return cap
        # self.price enthält schon den Münzfaktor des letzten Gangs, darum herausrechnen
        price = self.price / self.coin_mult * self.schedule(self.t0 + self.t)
        need = math.ceil(max(0.0, vis[0][5] - self.coins) / max(price, 1e-9))
        return min(cap, max(normal, need))

    def run(self):
        cap, rate = self.fill_target(), self.rate
        w = self.walk
        pre_t = 0.0
        if self.runs and self.hold_walk:
            pre_t = min(w, cap / (rate * self.hold))     # Sammelzeit auf dem Rückweg
        pre = pre_t * rate * self.hold
        gather = (cap - pre) / (rate * self.hold)
        if pre >= cap - 1e-9:                             # Tank schon auf dem Rückweg voll
            gather = 0.0
            w_to_stand = pre_t                            # zurück, so weit er gelaufen ist
        else:
            w_to_stand = w
        zone, tool = self.zone[0], self.tool
        # Münzfaktor zum Zeitpunkt des Verkaufs (Boost läuft in echter Zeit)
        self.coin_mult = self.schedule(self.t0 + self.t + gather + w_to_stand)
        find_coins = self._gather_finds(zone, self.t - pre_t, gather * self.hold + pre_t)
        self.t += gather + w_to_stand
        sand = cap * self.price
        earned = sand + find_coins
        self.coins += earned
        self.run_earned += earned
        if self.first_wood is None and self.run_earned >= WOOD_CRATE:
            self.first_wood = self.t
        if self.first_min is None and ss.crystals(self.run_earned) >= MIN_CRYSTALS:
            self.first_min = self.t
        back = w if not (pre >= cap - 1e-9) else pre_t
        run_len = gather + w_to_stand + (back if self.runs else 0.0)
        self.runs.append((self.t, tool, zone, gather, run_len, earned))
        self.trips.append((self.t, self.run_earned, earned / max(run_len, 1e-9)))
        self.buy(earned / max(run_len, 1e-9))
        self.t += back


def play(state, schedule, seed, t0=0.0, nodes=None, stop="tree_end", **kw):
    nodes = nodes or ss.tree()
    p = PassPlayer(random.Random(seed), state, nodes, schedule, t0=t0, **kw)
    while p.t < ss.MAX_RUN_S:
        p.run()
        c = ss.crystals(p.run_earned)
        if stop == "tree_end" and p.done() and "collect_tool_4" in p.owned and c >= MIN_CRYSTALS:
            break
        if stop == "tree_only" and p.done():
            break
    p.end_t = max((t for t, _, _, _ in p.log), default=None)
    return p


def campaign(schedule, runs=10, budget_s=None, max_runs=5000, **kw):
    """Läufe nacheinander, Sturm am Baumende. Die Spieluhr läuft über alle Läufe weiter."""
    state = ss.new_state()
    out, clock = [], 0.0
    r = 0
    while (budget_s is None and r < runs) or (budget_s is not None and clock < budget_s and r < max_runs):
        p = play(state, schedule, SEED + r, t0=clock, **kw)
        c = ss.crystals(p.run_earned)
        clock += p.t
        state["crystals"] += c
        state["granted"].add("sandstorm_1")
        state["bonus_bp"] = p.bonus_bp
        out.append(dict(run=r + 1, t=p.t, c=c, total=state["crystals"], clock=clock, p=p,
                        earned=p.run_earned))
        r += 1
    return out


def crystals_at(res, seconds):
    c = 0
    for x in res:
        if x["clock"] > seconds:
            break
        c = x["total"]
    return c


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


# ---------------------------------------------------------------------------
# Hauptteil
# ---------------------------------------------------------------------------

VARIANTS_COIN = [
    ("ohne", mult_const(1.0)),
    ("2x-Pass", mult_const(2.0)),
    ("1 Boost (30 min ab Start)", mult_boost(1.0, 1)),
    ("Pass + 1 Boost", mult_boost(2.0, 1)),
    ("dauerhaft x2 (Boost je Sitzung)", mult_const(2.0)),
    ("dauerhaft x3 (additiv: Pass + Boost)", mult_const(3.0)),
    ("dauerhaft x4 (Pass x Boost je Sitzung)", mult_const(4.0)),
]


def q1():
    section("1. Münzfaktor: Lauf 1, Sturm-Läufe, Kristalle (Sturm am Baumende, 5 s Weg, Glück-Ast gekauft)")
    res = {}
    print(f"  {'Variante':<40} {'Lauf 1':>7} {'Kr.':>4} {'Lauf 2':>7} {'Lauf 5':>7} {'Lauf 10':>8}"
          f" {'10 Läufe':>9} {'Kr. 10':>7} {'Kr./h':>6} {'Kr.@1h':>7} {'Kr.@3h':>7} {'Kr.@10h':>8}"
          f" {'Lauf<2min ab':>13} {'<1min ab':>9}")
    for name, sch in VARIANTS_COIN:
        ten = campaign(sch, runs=10)
        long = campaign(sch, budget_s=10 * 3600)
        res[name] = (ten, long)
        t10 = ten[-1]["clock"]
        u2 = next((x["run"] for x in long if x["t"] < 120), None)
        u2c = next((x["clock"] - x["t"] for x in long if x["t"] < 120), None)
        u1 = next((x["run"] for x in long if x["t"] < 60), None)
        print(f"  {name:<40} {fmt_t(ten[0]['t']):>7} {ten[0]['c']:>4} {fmt_t(ten[1]['t']):>7}"
              f" {fmt_t(ten[4]['t']):>7} {fmt_t(ten[9]['t']):>8} {fmt_t(t10):>9} {ten[-1]['total']:>7}"
              f" {ten[-1]['total'] / (t10 / 3600):>6.0f} {crystals_at(long, 3600):>7}"
              f" {crystals_at(long, 3 * 3600):>7} {crystals_at(long, 10 * 3600):>8}"
              f" {str(u2) + ' (' + fmt_t(u2c) + ')':>13} {str(u1):>9}")
    print()
    print("  Lauflänge und Kristalle je Stunde nach 1, 3 und 10 Stunden Spielzeit (Spätphase):")
    for name, (_, long) in res.items():
        parts = []
        for h in (1, 3, 10):
            x = next((y for y in long if y["clock"] >= h * 3600), long[-1])
            parts.append(f"{h} h: Lauf {x['run']:>4} dauert {fmt_t(x['t']):>5}, {x['c'] / (x['t'] / 3600):>5.0f} Kr./h")
        print(f"  {name:<40} " + " | ".join(parts))
    print()
    print("  Kristalle je Lauf (Sturm am Baumende), Lauf 1 bis 10:")
    for name, (ten, _) in res.items():
        print(f"  {name:<40} " + " ".join(f"{x['c']:>3}" for x in ten))
    print()
    print("  Fester Lauf statt Baumende: Sturm nach genau T Minuten Lauf 1 (Kristalle ~ Einnahmen^0,25)")
    for T in (12, 15):
        row = []
        for name, sch in VARIANTS_COIN[:2] + VARIANTS_COIN[5:]:
            p = PassPlayer(random.Random(SEED), ss.new_state(), ss.tree(), sch)
            while p.t < T * 60:
                p.run()
            row.append(f"{name.split(' (')[0]} {ss.crystals(p.run_earned)}")
        print(f"  T = {T} min: " + ", ".join(row))
    return res


def q2():
    section("2. Großer Tank: Wegzeit je Werkzeugphase (Lauf 1, Basis-Spieler) und Wirkung über den Baum")
    base = play(ss.new_state(), mult_const(1.0), SEED, stop="tree_only")
    print("  Gegen die Knoten zu Beginn (A) und Ende (E) jeder Phase. g = Tank / Rate (Sammelzeit),"
          " Gewinn = (g + 2w) / (g + w) - 1")
    sim = PassPlayer(random.Random(0), ss.new_state(), ss.tree(), mult_const(1.0))
    phase_rows, prev_tool = [], None
    snaps = []
    for t, i, _, _ in base.log:
        sim.owned.add(i)
        snaps.append((t, sim.tool, sim.capacity, sim.rate))
    by_tool = {}
    for t, tool, cap, rate in snaps:
        by_tool.setdefault(tool, []).append((cap, rate))
    zone_of = {"hand": "Dünenmeer", "shovel": "Dünenmeer", "bucket_chain": "Oase",
               "mini_digger": "Canyon", "vacuum_robot": "Salzsee", "mega_machine": "Salzsee/Ruinen"}
    print(f"  {'Phase':<14} {'Zone':<15} {'Tank A-E':>16} {'Rate A-E':>18} {'g A-E (s)':>12}"
          f" {'Weganteil':>10} {'Gewinn 5 s':>11} {'2 s':>6} {'0,5 s':>6}")
    for tool in st.PHASES:
        if tool not in by_tool:
            continue
        lst = by_tool[tool]
        (ca, ra), (ce, re_) = lst[0], lst[-1]
        ga, ge = ca / ra, ce / re_
        gm = (ga + ge) / 2
        gain = lambda w: ((gm + 2 * w) / (gm + w) - 1)
        print(f"  {st.TOOL_NAME[tool]:<14} {zone_of[tool]:<15} {fmt_n(ca):>7}-{fmt_n(ce):<8}"
              f" {ra:>8,.0f}-{re_:<9,.0f} {ga:>5.0f}-{ge:<5.0f} {10 / (gm + 10):>10.0%}"
              f" {gain(5):>11.0%} {gain(2):>6.0%} {gain(0.5):>6.0%}".replace(",", "."))
    print()
    print(f"  {'Variante':<36} {'Upg. 1':>7} {'Schaufel':>9} {'Eimerk.':>8} {'M-Bagger':>9} {'Saugr.':>7}"
          f" {'Großm.':>7} {'Baumende':>9} {'10 Läufe':>9} {'Läufe <15 s':>12}")
    for walk in (5.0, 2.0, 0.5):
        for bt in (False, True):
            for coin in (1.0, 2.0):
                if coin == 2.0 and walk != 5.0:
                    continue
                # Großer Tank: der Spieler nimmt die bessere Gewohnheit (immer voll oder früh verkaufen)
                opts = []
                for smart in ((True, False) if bt else (True,)):
                    p = play(ss.new_state(), mult_const(coin), SEED, stop="tree_only", walk=walk,
                             big_tank=bt, smart_sell=smart)
                    camp = campaign(mult_const(coin), runs=10, walk=walk, big_tank=bt, smart_sell=smart)
                    opts.append((camp[-1]["clock"], p.end_t, p, camp, smart))
                _, _, p, camp, smart = min(opts, key=lambda o: (o[0], o[1]))
                tt = st.times(p)
                short = sum(1 for r in p.runs if r[4] < 15) / len(p.runs)
                name = f"Weg {walk:g} s, {'Großer Tank' if bt else 'normaler Tank'}" + (", 2x" if coin > 1 else "")
                if bt:
                    name += " (früh)" if smart else " (voll)"
                print(f"  {name:<36} {fmt_t(tt.get('collect_rate_1')):>7} {fmt_t(tt.get('collect_tool_2')):>9}"
                      f" {fmt_t(tt.get('collect_tool_3')):>8} {fmt_t(tt.get('collect_tool_4')):>9}"
                      f" {fmt_t(tt.get('collect_tool_5')):>7} {fmt_t(tt.get('collect_tool_6')):>7}"
                      f" {fmt_t(p.end_t):>9} {fmt_t(camp[-1]['clock']):>9} {short:>12.0%}")
    print("  (voll) = verkauft immer den vollen Tank, (früh) = verkauft, sobald der nächste Knoten bezahlbar ist,"
          " nie unter der normalen Tankgröße. Gezeigt ist die schnellere Gewohnheit über 10 Läufe.")
    print("  Immer voll verkaufen verschiebt Upgrade 1 auf 35 s (erster Tank 30 Sand).")
    # Ende des Baums: g am Baumende, mit Holz-Deckel
    cap, rate = 1_500_000, 6000 * (1 + sum(n[7] for n in ss.tree() if n[6] == "rateBonus") / 10000)
    for item in (1.0, 1.448):
        g = cap / (rate * item)
        print(f"  Baumende (Tank 1,5 Mio., Rate {rate * item:,.0f}/s, Items x{item}): g = {g:.1f} s, Gewinn Großer Tank"
              f" bei 5 s Weg {(g + 10) / (g + 5) - 1:.0%}".replace(",", "."))


def q3():
    section("3. Auto-Dig gegen manuelles Halten (5 s Weg)")
    cases = [
        ("manuell ideal: hält 100 %, auch auf dem Rückweg", dict(hold=1.0, hold_walk=True)),
        ("manuell: hält 95 %, auch auf dem Rückweg", dict(hold=0.95, hold_walk=True)),
        ("manuell: hält 90 %, auch auf dem Rückweg", dict(hold=0.90, hold_walk=True)),
        ("manuell: hält 95 %, nur auf dem Feld", dict(hold=0.95)),
        ("manuell: hält 90 %, nur auf dem Feld", dict(hold=0.90)),
        ("manuell: hält 80 %, nur auf dem Feld", dict(hold=0.80)),
        ("Auto-Dig (100 %, sammelt auf dem Rückweg)", dict(autodig=True)),
        ("Auto-Dig + Großer Tank", dict(autodig=True, big_tank=True)),
    ]
    rows = {}
    for name, kw in cases:
        p = play(ss.new_state(), mult_const(1.0), SEED, stop="tree_only", **kw)
        camp = campaign(mult_const(1.0), runs=10, **kw)
        rows[name] = (p.end_t, camp[-1]["clock"], camp[-1]["total"])
    ad = rows["Auto-Dig (100 %, sammelt auf dem Rückweg)"]
    print(f"  {'Spielweise':<48} {'Baumende L1':>12} {'10 Läufe':>9} {'Kristalle':>10} {'Auto-Dig mehr je h':>19}")
    for name, (e1, t10, c) in rows.items():
        print(f"  {name:<48} {fmt_t(e1):>12} {fmt_t(t10):>9} {c:>10} {t10 / ad[1] - 1:>+19.0%}")
    print()
    print("  Je Gang (analytisch, g = Sammelzeit bei vollem Halten, 5 s Weg):")
    for g in (10, 15, 20, 30):
        man = {h: g / h + 10 for h in (1.0, 0.95, 0.9, 0.8)}
        auto = g + 5 if g > 5 else 2 * g
        print(f"  g = {g:>2} s: Auto-Dig-Gang {auto:>4.0f} s, manuell 100/95/90/80 % "
              + "/".join(f"{v:.0f}" for v in man.values()) + " s, Mehrertrag "
              + "/".join(f"{v / auto - 1:+.0%}" for v in man.values()))
    print()
    print("  AFK (Auto-Dig an, niemand verkauft): genau ein Tank, dann Stopp.")
    sim = PassPlayer(random.Random(0), ss.new_state(), ss.tree(), mult_const(1.0))
    for t, i, _, _ in play(ss.new_state(), mult_const(1.0), SEED, stop="tree_only").log:
        sim.owned.add(i)
    for bt in (False, True):
        sim.big_tank = bt
        g = sim.capacity / sim.rate
        print(f"  Baumende {'mit' if bt else 'ohne'} Großem Tank: ein Tank = {g:.0f} s aktiver Ertrag,"
              f" also {g / 3600:.1%} einer aktiven Stunde je Stunde AFK")


def q4(res):
    section("4. x4 (Pass x Boost) gegen additiv x3: Lauf 1, Holzkiste, Sturm-Schwelle")
    print(f"  {'Faktor':<8} {'Upg. 1':>7} {'Schaufel':>9} {'M-Bagger':>9} {'Großm.':>7} {'Baumende':>9}"
          f" {'25K verdient':>13} {'Schwelle 20 Kr.':>16} {'Holzk. = s Ertrag (Saugr./Baumende)':>36}"
          f" {'Holz-Deckel = s':>16}")
    for m in (1.0, 2.0, 3.0, 4.0, 6.0):
        p = play(ss.new_state(), mult_const(m), SEED, stop="tree_end")
        tt = st.times(p)
        t5 = tt.get("collect_tool_5")
        inc5 = next(c for t, e, c in p.trips if t >= t5)
        inc_end = p.trips[-1][2]
        label = "x4+Fr." if m == 6.0 else f"x{m:g}"
        print(f"  {label:<8} {fmt_t(tt.get('collect_rate_1')):>7} {fmt_t(tt.get('collect_tool_2')):>9}"
              f" {fmt_t(tt.get('collect_tool_4')):>9} {fmt_t(tt.get('collect_tool_6')):>7} {fmt_t(p.end_t):>9}"
              f" {fmt_t(p.first_wood):>13} {fmt_t(p.first_min):>16}"
              f" {WOOD_CRATE / inc5:>17.2f} / {WOOD_CRATE / inc_end:<16.3f} {WOOD_CAP_COST / inc_end:>16.1f}")
    print("  x4+Fr. = x4 mit vollem Freunde-Bonus (+50 %), also x6 auf alle Münzen.")
    print()
    print("  Boost-Wert je Kauf (49 Robux) für Pass-Besitzer: x4 verdoppelt, x3 gibt nur +50 %.")
    ten = {k: v[0] for k, v in res.items()}
    for a, b in (("ohne", "1 Boost (30 min ab Start)"), ("2x-Pass", "Pass + 1 Boost")):
        d = ten[a][-1]["clock"] - ten[b][-1]["clock"]
        print(f"  {b:<28} spart gegenüber {a:<8} über 10 Läufe {fmt_t(d)} Spielzeit")
    for a in ("2x-Pass",):
        s = campaign(mult_boost(2.0, 1, combine="add"), runs=10)
        d = ten[a][-1]["clock"] - s[-1]["clock"]
        print(f"  Pass + 1 Boost additiv (x3) spart gegenüber 2x-Pass über 10 Läufe {fmt_t(d)} Spielzeit")
    print()
    print("  Robux-Vergleich: dauerhaft x2 über Boosts kostet 98 Robux je Stunde Spiel (2 Boosts),"
          f" der Pass amortisiert sich nach {PRICE['double_coins'] / 98:.1f} h Dauerspiel oder nach"
          f" {PRICE['double_coins'] / PRICE['coin_boost']:.1f} Sitzungen mit je einem Boost.")
    for sess in (10, 15, 30, 60):
        used = min(sess, 30) / 30
        print(f"  Sitzung {sess:>2} min, Boost bei Sitzungsstart: {used:.0%} der Boostzeit genutzt"
              + (" (Rest läuft offline ab)" if sess < 30 else ""))


def main():
    section("0. Abgleich mit src/shared/Data")
    for line in check_data():
        print(line)
    res = q1()
    q2()
    q3()
    q4(res)


if __name__ == "__main__":
    main()
