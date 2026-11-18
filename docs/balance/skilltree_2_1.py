#!/usr/bin/env python3
"""Dune Baron, Paket 2.1: Zahlen für den ganzen Skilltree des ersten Durchgangs.

Simuliert einen Spieler von der Hand bis zum letzten Knoten vor dem ersten Sandsturm
(etwas hinter der Großmaschine) mit derselben Schleife wie phase0_startwerte.py und
tests/tutorial.spec.luau: sammeln bis der Tank voll ist, 5 s zum Händler, verkaufen,
Knoten kaufen, 5 s zurück zum Feld.

Kaufregel wie TreePurchase.visible im Lune-Test: den billigsten sichtbaren Knoten kaufen,
solange das Geld reicht, sonst sparen. Die Basis kauft keine Glück-Knoten, die Varianten
zeigen Glück, Fundverkauf, Gamepässe, Auto-Dig und den Baum ohne Tore an den Werkzeugen.
Ergebnis und Begründungen: docs/balance/skilltree_2_1.md.

Nur Standardbibliothek. Aufruf: python3 docs/balance/skilltree_2_1.py
Zufall gibt es nur in der Fund-Simulation (Monte Carlo), sie nutzt feste Seeds.
"""

import math
import random

# ---------------------------------------------------------------------------
# Feste Vorgaben (src/shared/Data: Tools, Zones, SandTypes, Economy)
# ---------------------------------------------------------------------------

TOOLS = [  # id, Stufe, Sand pro Sekunde, Preis, Knoten
    ("hand", 1, 1, 0, None),
    ("shovel", 2, 5, 50, "collect_tool_2"),
    ("bucket_chain", 3, 25, 600, "collect_tool_3"),
    ("mini_digger", 4, 150, 7_500, "collect_tool_4"),
    ("vacuum_robot", 5, 900, 90_000, "collect_tool_5"),
    ("mega_machine", 6, 6_000, 1_100_000, "collect_tool_6"),
]
TOOL_RATE = {t[0]: t[2] for t in TOOLS}
TOOL_TIER = {t[0]: t[1] for t in TOOLS}
TOOL_NAME = {
    "hand": "Hand", "shovel": "Schaufel", "bucket_chain": "Eimerkette",
    "mini_digger": "Mini-Bagger", "vacuum_robot": "Saugroboter", "mega_machine": "Großmaschine",
}

ZONES = [  # id, Sandfaktor, Knoten, Fundchance-Faktor (phase0)
    ("dunes", 1, None, 1.0),
    ("oasis", 3, "collect_tool_3", 1.2),
    ("canyon", 10, "collect_tool_4", 1.4),
    ("salt_lake", 40, "collect_tool_5", 1.6),
]
ZONE_NAME = {"dunes": "Dünenmeer", "oasis": "Oase", "canyon": "Canyon", "salt_lake": "Salzsee"}

BASE_COINS_PER_SAND = 1
START_TANK_CAPACITY = 15
BIG_TANK_MULTIPLIER = 2
FIND_CHANCE_PER_SECOND = 0.02
FIND_BASE_VALUE = 3
RARITIES = [  # id, Anteil, Wertfaktor
    ("gewoehnlich", 0.70, 1),
    ("ungewoehnlich", 0.22, 4),
    ("selten", 0.06, 15),
    ("episch", 0.016, 60),
    ("legendaer", 0.0035, 300),
    ("mythisch", 0.0005, 1500),
]
EV_RARITY_FACTOR = sum(s * f for _, s, f in RARITIES)

# ---------------------------------------------------------------------------
# Vorschlag: der Skilltree des ersten Durchgangs
# (id, Spieler-Name, Beschreibung, Ast, requires, Preis, Wirkung, Wert)
# Wirkungen: setTool (Werkzeug-ID), rateBonus / sellBonus / luckBonus (bp, 10000 = 100 %),
#            setTank (neue Gesamtkapazität in Sand)
# FEST = Vorgabe aus Paket 1.6 oder Tools.luau, wird nicht verändert.
# ---------------------------------------------------------------------------

NODES = [
    # --- Hand (Dünenmeer) --------------------------------------------------------
    ("collect_rate_1", "Kräftigere Hände", "+50 % Sand pro Sekunde", "collect",
     [], 15, "rateBonus", 5000),                                              # FEST
    ("tank_1", "Größerer Beutel", "Tank 30", "tank",
     [], 20, "setTank", 30),                                                  # FEST
    ("collect_tool_2", "Schaufel", "Werkzeug: Schaufel, gräbt eine Mulde", "collect",
     [], 50, "setTool", "shovel"),                                            # FEST
    # --- Schaufel (Dünenmeer) ----------------------------------------------------
    ("tank_2", "Rucksack", "Tank 60", "tank",
     ["tank_1"], 60, "setTank", 60),                                          # FEST
    ("luck_1", "Scharfes Auge", "+10 % Fundchance", "luck",
     ["collect_tool_2"], 30, "luckBonus", 1000),
    ("collect_rate_2", "Geübter Griff", "+25 % Sand pro Sekunde", "collect",
     ["collect_tool_2"], 120, "rateBonus", 2500),                             # FEST
    ("sell_1", "Feilschen", "+20 % Münzen pro Sand", "sell",
     ["collect_tool_2"], 150, "sellBonus", 2000),
    ("tank_3", "Sandsack", "Tank 150", "tank",
     ["tank_2"], 250, "setTank", 150),                                        # FEST
    ("collect_rate_3", "Schneller Spaten", "+25 % Sand pro Sekunde", "collect",
     ["collect_rate_2"], 300, "rateBonus", 2500),
    ("collect_tool_3", "Eimerkette", "Werkzeug: Eimerkette, Band trägt Sand zum Tank", "collect",
     ["collect_tool_2"], 600, "setTool", "bucket_chain"),                     # FEST Preis
    # --- Eimerkette (Oase) -------------------------------------------------------
    ("tank_4", "Lederschlauch", "Tank 400", "tank",
     ["tank_3", "collect_tool_3"], 500, "setTank", 400),
    ("luck_2", "Wünschelrute", "+10 % Fundchance", "luck",
     ["luck_1", "collect_tool_3"], 800, "luckBonus", 1000),
    ("sell_2", "Marktkenntnis", "+20 % Münzen pro Sand", "sell",
     ["sell_1", "collect_tool_3"], 1_000, "sellBonus", 2000),
    ("collect_rate_4", "Schnelle Eimer", "+50 % Sand pro Sekunde", "collect",
     ["collect_rate_3", "collect_tool_3"], 1_500, "rateBonus", 5000),
    ("tank_5", "Wasserfass", "Tank 1K", "tank",
     ["tank_4"], 2_500, "setTank", 1_000),
    ("collect_rate_5", "Doppelte Kette", "+50 % Sand pro Sekunde", "collect",
     ["collect_rate_4"], 4_000, "rateBonus", 5000),
    ("sell_3", "Oasenmarkt", "+30 % Münzen pro Sand", "sell",
     ["sell_2"], 6_000, "sellBonus", 3000),
    ("tank_6", "Karrenladung", "Tank 2K", "tank",
     ["tank_5"], 8_000, "setTank", 2_000),
    ("collect_rate_6", "Lange Kette", "+50 % Sand pro Sekunde", "collect",
     ["collect_rate_5"], 12_000, "rateBonus", 5000),
    ("collect_tool_4", "Mini-Bagger", "Werkzeug: Mini-Bagger, Fahrzeug mit Staubwolke", "collect",
     ["collect_tool_3", "collect_rate_6"], 7_500, "setTool", "mini_digger"),  # FEST Preis
    # --- Mini-Bagger (Canyon) ----------------------------------------------------
    ("tank_7", "Kipplader", "Tank 6K", "tank",
     ["tank_6", "collect_tool_4"], 100_000, "setTank", 6_000),
    ("sell_4", "Canyon-Handel", "+30 % Münzen pro Sand", "sell",
     ["sell_3", "collect_tool_4"], 200_000, "sellBonus", 3000),
    ("luck_3", "Spürnase", "+15 % Fundchance", "luck",
     ["luck_2", "collect_tool_4"], 50_000, "luckBonus", 1500),
    ("collect_rate_7", "Baggerlöffel", "+75 % Sand pro Sekunde", "collect",
     ["collect_rate_6", "collect_tool_4"], 300_000, "rateBonus", 7500),
    ("tank_8", "Container", "Tank 15K", "tank",
     ["tank_7"], 400_000, "setTank", 15_000),
    ("collect_rate_8", "Turbomotor", "+100 % Sand pro Sekunde", "collect",
     ["collect_rate_7"], 750_000, "rateBonus", 10000),
    ("sell_5", "Karawanenhandel", "+50 % Münzen pro Sand", "sell",
     ["sell_4"], 500_000, "sellBonus", 5000),
    ("collect_tool_5", "Saugroboter", "Werkzeug: Saugroboter, saugt die Fläche leer", "collect",
     ["collect_tool_4", "collect_rate_8"], 90_000, "setTool", "vacuum_robot"),        # FEST Preis
    # --- Saugroboter (Salzsee) ---------------------------------------------------
    ("tank_9", "Silo", "Tank 60K", "tank",
     ["tank_8", "collect_tool_5"], 3_000_000, "setTank", 60_000),
    ("luck_4", "Salzkompass", "+15 % Fundchance", "luck",
     ["luck_3", "collect_tool_5"], 5_000_000, "luckBonus", 1500),
    ("collect_rate_9", "Starker Sog", "+100 % Sand pro Sekunde", "collect",
     ["collect_rate_8", "collect_tool_5"], 10_000_000, "rateBonus", 10000),
    ("sell_6", "Salzhändler", "+50 % Münzen pro Sand", "sell",
     ["sell_5", "collect_tool_5"], 15_000_000, "sellBonus", 5000),
    ("tank_10", "Speicherturm", "Tank 150K", "tank",
     ["tank_9"], 20_000_000, "setTank", 150_000),
    ("collect_rate_10", "Doppelrüssel", "+150 % Sand pro Sekunde", "collect",
     ["collect_rate_9"], 35_000_000, "rateBonus", 15000),
    ("collect_tool_6", "Großmaschine", "Werkzeug: Großmaschine, frisst ganze Dünen", "collect",
     ["collect_tool_5", "collect_rate_10"], 1_100_000, "setTool", "mega_machine"),  # FEST Preis
    # --- Großmaschine (Salzsee) --------------------------------------------------
    ("sell_7", "Kristallbörse", "+75 % Münzen pro Sand", "sell",
     ["sell_6", "collect_tool_6"], 100_000_000, "sellBonus", 7500),
    ("tank_11", "Frachtzug", "Tank 800K", "tank",
     ["tank_10", "collect_tool_6"], 60_000_000, "setTank", 800_000),
    ("luck_5", "Sternkarte", "+20 % Fundchance", "luck",
     ["luck_4", "collect_tool_6"], 100_000_000, "luckBonus", 2000),
    ("collect_rate_11", "Dünenfresser", "+200 % Sand pro Sekunde", "collect",
     ["collect_rate_10", "collect_tool_6"], 200_000_000, "rateBonus", 20000),
    ("sell_8", "Wüstenbaron", "+100 % Münzen pro Sand", "sell",
     ["sell_7"], 300_000_000, "sellBonus", 10000),
    ("tank_12", "Dünenspeicher", "Tank 1,5M", "tank",
     ["tank_11"], 400_000_000, "setTank", 1_500_000),
    ("luck_6", "Glück der Wüste", "+30 % Fundchance", "luck",
     ["luck_5"], 150_000_000, "luckBonus", 3000),
    ("collect_rate_12", "Sturmkraft", "+250 % Sand pro Sekunde", "collect",
     ["collect_rate_11"], 600_000_000, "rateBonus", 25000),
]

MILESTONES = ["collect_rate_1", "collect_tool_2", "collect_tool_3", "collect_tool_4",
              "collect_tool_5", "collect_tool_6"]
MILESTONE_LABEL = {
    "collect_rate_1": "Upgrade 1", "collect_tool_2": "Schaufel", "collect_tool_3": "Eimerkette",
    "collect_tool_4": "Mini-Bagger", "collect_tool_5": "Saugroboter",
    "collect_tool_6": "Großmaschine", "END": "Baum fertig",
}

NODE = {n[0]: n for n in NODES}

# Gegenprobe ohne Tore: Werkzeug-Knoten verlangen nur das vorige Werkzeug (wie vor Paket 2.1).
NODES_NO_GATES = [
    n if n[6] != "setTool" else n[:4] + ([r for r in n[4] if r.startswith("collect_tool")],) + n[5:]
    for n in NODES
]

# ---------------------------------------------------------------------------
# Annahmen der Simulation
# ---------------------------------------------------------------------------

WALK_ONE_WAY_S = 5.0
MAX_SIM_S = 4 * 3600
RUN_BAND = (15.0, 40.0)


class Player:
    def __init__(self, coin_mult=1.0, big_tank=False, autodig=False, buy_luck=False,
                 find_coins=False, rule="strict", nodes=None):
        self.nodes = nodes or NODES
        self.node = {n[0]: n for n in self.nodes}
        self.coin_mult = coin_mult
        self.big_tank = big_tank
        self.autodig = autodig
        self.buy_luck = buy_luck
        self.find_coins = find_coins
        self.rule = rule
        self.owned = set()
        self.coins = 0.0
        self.t = 0.0
        self.log = []    # (t, id, Preis, Einkommen pro s vor dem Kauf)
        self.runs = []   # (t_ende, Werkzeug, Zone, Sammelzeit, Laufzeit, Münzen)

    # -- Zustand aus den Knoten ------------------------------------------------
    def _sum(self, kind):
        return sum(self.node[i][7] for i in self.owned if self.node[i][6] == kind)

    @property
    def tool(self):
        best = "hand"
        for i in self.owned:
            n = self.node[i]
            if n[6] == "setTool" and TOOL_TIER[n[7]] > TOOL_TIER[best]:
                best = n[7]
        return best

    @property
    def zone(self):
        best = ZONES[0]
        for z in ZONES:
            if z[2] is None or z[2] in self.owned:
                best = z
        return best

    @property
    def rate(self):
        return TOOL_RATE[self.tool] * (10000 + self._sum("rateBonus")) / 10000

    @property
    def capacity(self):
        base = START_TANK_CAPACITY
        for i in self.owned:
            n = self.node[i]
            if n[6] == "setTank":
                base = max(base, n[7])
        return math.floor(base * (BIG_TANK_MULTIPLIER if self.big_tank else 1))

    @property
    def price(self):
        sf = self.zone[1]
        return BASE_COINS_PER_SAND * sf * (10000 + self._sum("sellBonus")) / 10000 * self.coin_mult

    @property
    def luck(self):
        return (10000 + self._sum("luckBonus")) / 10000

    def find_coins_per_gather_s(self):
        """Erwartete Münzen aus Funden je Sammelsekunde, wenn jeder Fund verkauft wird."""
        z = self.zone
        p = FIND_CHANCE_PER_SECOND * z[3] * self.luck
        value = FIND_BASE_VALUE * z[1] * TOOL_RATE[self.tool] * EV_RARITY_FACTOR
        return p * value * self.coin_mult

    # -- Baum --------------------------------------------------------------------
    def visible(self):
        out = []
        for n in self.nodes:
            if n[0] in self.owned:
                continue
            if n[3] == "luck" and not self.buy_luck:
                continue
            if all(r in self.owned for r in n[4]):
                out.append(n)
        out.sort(key=lambda n: (n[5], n[0]))
        return out

    def buy(self, income):
        while True:
            vis = self.visible()
            if not vis:
                return
            if self.rule == "strict":
                node = vis[0]          # wie TreePurchase.visible()[1] im Lune-Test
                if node[5] > self.coins:
                    return
            else:                      # phase0: billigster bezahlbarer
                ok = [n for n in vis if n[5] <= self.coins]
                if not ok:
                    return
                node = ok[0]
            self.coins -= node[5]
            self.owned.add(node[0])
            self.log.append((self.t, node[0], node[5], income))

    def done(self):
        return not self.visible()

    # -- ein Durchlauf ab dem Feld -------------------------------------------------
    def run(self):
        t0 = self.t
        cap, rate = self.capacity, self.rate
        start = min(cap, rate * WALK_ONE_WAY_S) if (self.autodig and self.runs) else 0.0
        gather = (cap - start) / rate
        self.t += gather + WALK_ONE_WAY_S
        earned = cap * self.price
        if self.find_coins and TOOL_TIER[self.tool] >= 2:
            earned += gather * self.find_coins_per_gather_s()
        self.coins += earned
        run_len = gather + 2 * WALK_ONE_WAY_S
        self.runs.append((self.t, self.tool, self.zone[0], gather, run_len, earned))
        self.buy(earned / run_len)
        self.t += WALK_ONE_WAY_S
        return t0


def simulate(**kw):
    p = Player(**kw)
    while p.t < MAX_SIM_S and not p.done():
        p.run()
    main_ids = [t for t, i, _, _ in p.log if p.node[i][3] != "luck"]
    p.end_t = main_ids[-1] if main_ids else None
    return p


def times(p):
    out = {}
    for t, i, _, _ in p.log:
        out.setdefault(i, t)
    out["END"] = p.end_t
    return out


def fmt_t(s):
    if s is None:
        return "-"
    m, sec = divmod(int(round(s)), 60)
    return f"{m}:{sec:02d}" if m else f"{sec} s"


def fmt_n(x):
    if x >= 1e9:
        return f"{x / 1e9:.2f}".rstrip("0").rstrip(".").replace(".", ",") + " Mrd."
    if x >= 1e6:
        return f"{x / 1e6:.2f}".rstrip("0").rstrip(".").replace(".", ",") + " Mio."
    return f"{int(round(x)):,}".replace(",", ".")


# ---------------------------------------------------------------------------
# Auswertung
# ---------------------------------------------------------------------------

PHASES = ["hand", "shovel", "bucket_chain", "mini_digger", "vacuum_robot", "mega_machine"]


def phase_of(p, t):
    tool = "hand"
    for tt, i, _, _ in p.log:
        if tt > t:
            break
        n = p.node[i]
        if n[6] == "setTool":
            tool = n[7]
    return tool


def gaps_by_phase(p):
    res = {ph: [] for ph in PHASES}
    prev = 0.0
    for t, i, _, _ in p.log:
        ph = phase_of(p, prev)
        res[ph].append((t - prev, i))
        prev = t
    return res


def runs_by_phase(p):
    res = {ph: [] for ph in PHASES}
    for r in p.runs:
        res[r[1]].append(r)
    return res


def income_curve(p, step=60):
    """Münzen pro Sekunde im Mittel je Minute (Ertrag der Läufe, die in der Minute enden)."""
    buckets = {}
    for r in p.runs:
        m = int(r[0] // step)
        buckets.setdefault(m, [0.0, 0.0])
        buckets[m][0] += r[5]
        buckets[m][1] += r[4]
    return {m: v[0] / v[1] for m, v in sorted(buckets.items())}


def mc_finds(p, seed, trials=2000):
    """Monte Carlo: Funde je Seltenheit über die Sammelsekunden eines Laufs (mit Glück der Knoten)."""
    rng = random.Random(seed)
    # Glück je Lauf aus dem Kaufprotokoll nachbauen
    luck_at = []
    luck = 1.0
    events = [(t, p.node[i]) for t, i, _, _ in p.log]
    k = 0
    for r in p.runs:
        while k < len(events) and events[k][0] < r[0] - r[3] - WALK_ONE_WAY_S + 1e-9:
            n = events[k][1]
            if n[6] == "luckBonus":
                luck += n[7] / 10000
            k += 1
        zf = dict((z[0], z[3]) for z in ZONES)[r[2]]
        luck_at.append((r[3], FIND_CHANCE_PER_SECOND * zf * luck))
    lam = sum(g * q for g, q in luck_at)  # erwartete Funde gesamt
    counts = {rid: 0 for rid, _, _ in RARITIES}
    totals = []
    for _ in range(trials):
        n = 0
        for g, q in luck_at:
            whole = int(g)
            for _s in range(whole):
                if rng.random() < q:
                    n += 1
            if rng.random() < 1 - (1 - q) ** (g - whole):
                n += 1
        totals.append(n)
    # Seltenheiten erwartungstreu verteilen
    mean = sum(totals) / trials
    for rid, share, _ in RARITIES:
        counts[rid] = mean * share
    return lam, mean, counts


def main():
    base = simulate()
    tb = times(base)

    print("=== Basis: Kaufprotokoll (Regel: billigster sichtbarer Knoten, sonst sparen; ohne Glück) ===")
    for t, i, c, inc in base.log:
        n = base.node[i]
        secs = c / inc if inc > 0 else float("inf")
        print(f"  {fmt_t(t):>6}  {i:<15} {fmt_n(c):>12}  = {secs:6.0f} s Ertrag   ({n[1]}, {n[2]})")
    print()

    print("=== Meilensteine (Basis) ===")
    for m in MILESTONES + ["END"]:
        print(f"  {MILESTONE_LABEL[m]:<14} {fmt_t(tb.get(m)):>7}")
    print()

    print("=== Pausen zwischen Käufen je Phase (Basis) ===")
    for ph, gs in gaps_by_phase(base).items():
        if not gs:
            continue
        g, i = max(gs)
        avg = sum(x for x, _ in gs) / len(gs)
        print(f"  {TOOL_NAME[ph]:<13} Käufe {len(gs):>2}  Mittel {avg:5.0f} s  längste {g:5.0f} s vor {i}")
    print()

    print("=== Durchlauflänge (Sammeln + 10 s Weg) je Phase (Basis) ===")
    for ph, rs in runs_by_phase(base).items():
        if not rs:
            continue
        lens = sorted(r[4] for r in rs)
        inside = sum(1 for x in lens if RUN_BAND[0] <= x <= RUN_BAND[1]) / len(lens)
        print(f"  {TOOL_NAME[ph]:<13} Läufe {len(lens):>3}  Median {lens[len(lens) // 2]:5.1f} s"
              f"  Min {lens[0]:5.1f} s  Max {lens[-1]:5.1f} s  im Band 15-40 s: {inside:4.0%}")
    allr = [r[4] for r in base.runs]
    print(f"  Gesamt: {sum(1 for x in allr if RUN_BAND[0] <= x <= RUN_BAND[1]) / len(allr):.0%} "
          f"der Läufe im Band, {sum(r[4] for r in base.runs if RUN_BAND[0] <= r[4] <= RUN_BAND[1]) / sum(allr):.0%} der Spielzeit")
    print()

    print("=== Ertrag in Münzen pro Sekunde je Minute (Basis) ===")
    curve = income_curve(base)
    prev = 0
    stalls = []
    line = []
    for m, v in curve.items():
        line.append(f"{m}:{v:,.0f}".replace(",", "."))
        if v < prev * 0.999:
            stalls.append(m)
        prev = max(prev, v)
    for k in range(0, len(line), 8):
        print("  " + "  ".join(line[k:k + 8]))
    print(f"  Minuten mit sinkendem Ertrag: {stalls if stalls else 'keine'}")
    print()

    print("=== Varianten: Meilensteine ===")
    variants = [
        ("Basis (Vorschlag)", dict()),
        ("Regel phase0 (billigster bezahlbarer)", dict(rule="phase0")),
        ("Mit Glück-Ast (ohne Fundwert)", dict(buy_luck=True)),
        ("Mit Glück-Ast und Fundverkauf", dict(buy_luck=True, find_coins=True)),
        ("Ohne Glück, mit Fundverkauf", dict(find_coins=True)),
        ("Gamepass Großer Tank x2", dict(big_tank=True)),
        ("Gamepass 2x Münzen", dict(coin_mult=2.0)),
        ("2x Münzen und Großer Tank", dict(coin_mult=2.0, big_tank=True)),
        ("Auto-Dig (obere Schranke)", dict(autodig=True)),
        ("Ohne Tore an den Werkzeugen", dict(nodes=NODES_NO_GATES)),
    ]
    cols = MILESTONES + ["END"]
    print(f"  {'Variante':<40}" + "".join(f"{MILESTONE_LABEL[c]:>14}" for c in cols)
          + f"{'Band 15-40 s':>14}")
    results = {}
    for name, kw in variants:
        p = simulate(**kw)
        tt = times(p)
        results[name] = (p, tt)
        band = sum(r[4] for r in p.runs if RUN_BAND[0] <= r[4] <= RUN_BAND[1]) / sum(r[4] for r in p.runs)
        print(f"  {name:<40}" + "".join(f"{fmt_t(tt.get(c)):>14}" for c in cols) + f"{band:>14.0%}")
    print()

    print("=== Empfindlichkeit: Laufweg je Richtung ===")
    global WALK_ONE_WAY_S
    saved = WALK_ONE_WAY_S
    for w in (3.0, 5.0, 8.0):
        WALK_ONE_WAY_S = w
        tt = times(simulate())
        print(f"  {w:.0f} s: " + ", ".join(f"{MILESTONE_LABEL[c]} {fmt_t(tt.get(c))}" for c in cols[1:]))
    WALK_ONE_WAY_S = saved
    print()

    print("=== Glück-Ast als Nebenkauf ===")
    pl, tl = results["Mit Glück-Ast (ohne Fundwert)"]
    for c in cols[2:]:
        d = tl[c] - tb[c]
        print(f"  {MILESTONE_LABEL[c]:<14} {fmt_t(tb[c]):>7} -> {fmt_t(tl[c]):>7}  (+{d:.0f} s, {d / tb[c]:+.1%})")
    luck_cost = sum(n[5] for n in NODES if n[3] == "luck")
    print(f"  Summe Glück-Knoten: {fmt_n(luck_cost)} Münzen")
    for t, i, c, inc in pl.log:
        if i.startswith("luck"):
            print(f"  {i:<8} gekauft {fmt_t(t):>6}, kostet {c / inc:5.0f} s Ertrag")
    print()

    print("=== Funde bis zum Ende des Baums (Monte Carlo, Seed 21 und 22) ===")
    for name, seed in (("Basis (Vorschlag)", 21), ("Mit Glück-Ast (ohne Fundwert)", 22)):
        p, _ = results[name]
        lam, mean, counts = mc_finds(p, seed)
        rare_plus = sum(counts[r] for r in ("selten", "episch", "legendaer", "mythisch"))
        print(f"  {name:<32} erwartet {lam:5.1f}, MC {mean:5.1f} Funde, davon Selten+ {rare_plus:4.2f}")
    print()

    print("=== Fundverkauf: Anteil am Ertrag, wenn jeder Fund verkauft wird ===")
    p, _ = results["Ohne Glück, mit Fundverkauf"]
    print("  (Anteil je Phase mit den Knoten zu Phasenbeginn, ohne Glück)")
    sim = Player(find_coins=True)
    for t, i, _, _ in p.log:
        n = sim.node[i]
        sim.owned.add(i)
        if n[6] == "setTool":
            g = sim.capacity / sim.rate
            f = g * sim.find_coins_per_gather_s()
            s = sim.capacity * sim.price
            print(f"  {TOOL_NAME[sim.tool]:<13} {f / (f + s):5.1%}")
    print()

    print("=== Gamepass-Wirkung (Zeit bis Meilenstein, relativ zur Basis) ===")
    for name in ("Gamepass Großer Tank x2", "Gamepass 2x Münzen", "2x Münzen und Großer Tank",
                 "Auto-Dig (obere Schranke)"):
        _, tt = results[name]
        parts = []
        for c in cols[2:]:
            parts.append(f"{MILESTONE_LABEL[c]} {(tt[c] - tb[c]) / tb[c]:+.0%}")
        print(f"  {name:<28} " + ", ".join(parts))
    print()

    print("=== Werkzeugpreis gegen Knotenkosten je Phase (Basis) ===")
    spend = {ph: [0, 0] for ph in PHASES}
    for t, i, c, _ in base.log:
        n = base.node[i]
        ph = phase_of(base, t - 1e-6)
        if n[6] == "setTool":
            spend[ph][1] += c
        else:
            spend[ph][0] += c
    for ph in PHASES:
        k, w = spend[ph]
        if k or w:
            print(f"  {TOOL_NAME[ph]:<13} Knoten {fmt_n(k):>12}  nächstes Werkzeug {fmt_n(w):>12}")
    print()

    print("=== Größen ===")
    for br in ("collect", "tank", "sell", "luck"):
        ids = [n[0] for n in NODES if n[3] == br and n[6] != "setTool"]
        print(f"  {br:<8} {len(ids):>2} Knoten")
    print(f"  Summe aller Endwerte: Rate +{sum(n[7] for n in NODES if n[6] == 'rateBonus') / 100:.0f} %, "
          f"Verkauf +{sum(n[7] for n in NODES if n[6] == 'sellBonus') / 100:.0f} %, "
          f"Glück +{sum(n[7] for n in NODES if n[6] == 'luckBonus') / 100:.0f} %, "
          f"Tank {fmt_n(max(n[7] for n in NODES if n[6] == 'setTank'))}")


if __name__ == "__main__":
    main()
