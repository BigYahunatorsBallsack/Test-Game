#!/usr/bin/env python3
"""Dune Baron, Paket 0.1: Startwerte, die im Konzept fehlen.

Simuliert die ersten Spielminuten (Hand bis Mini-Bagger) mit einer festen
Durchlauf-Schleife: zum Sandfeld laufen, sammeln bis der Tank voll ist,
zum Händler laufen, verkaufen, Knoten kaufen.

Nur Standardbibliothek. Aufruf: python3 docs/balance/phase0_startwerte.py
Alle Zufallsläufe nutzen feste Seeds, die Ausgabe ist reproduzierbar.
"""

import math
import random

# ---------------------------------------------------------------------------
# Feste Vorgaben aus docs/konzept.md
# ---------------------------------------------------------------------------

TOOLS = [  # id, Sand pro Sekunde, Preis
    ("hand", 1, 0),
    ("schaufel", 5, 50),
    ("eimerkette", 25, 600),
    ("minibagger", 150, 7_500),
    ("saugroboter", 900, 90_000),
    ("grossmaschine", 6_000, 1_100_000),
]
TOOL_RATE = {t: r for t, r, _ in TOOLS}
TOOL_PRICE = {t: p for t, _, p in TOOLS}

ZONES = [  # id, Sandfaktor, freigeschaltet durch Werkzeug
    ("duenenmeer", 1, "hand"),
    ("oase", 3, "eimerkette"),
    ("canyon", 10, "minibagger"),
    ("salzsee", 40, "saugroboter"),
    ("ruinenstadt", 150, None),  # erster Sandsturm
]
SAND_FACTOR = {z: f for z, f, _ in ZONES}

RARITIES = [  # id, Anteil, Wertfaktor
    ("gewoehnlich", 0.70, 1),
    ("ungewoehnlich", 0.22, 4),
    ("selten", 0.06, 15),
    ("episch", 0.016, 60),
    ("legendaer", 0.0035, 300),
    ("mythisch", 0.0005, 1500),
]
assert abs(sum(r[1] for r in RARITIES) - 1.0) < 1e-9
EV_RARITY_FACTOR = sum(share * factor for _, share, factor in RARITIES)

GOLD_LEG_PLUS = 0.045 + 0.005
GOLD_PITY_LEG = 60
GOLD_PRICE_GEMS = 400

# ---------------------------------------------------------------------------
# Vorgeschlagene Startwerte (das Ergebnis dieses Pakets)
# ---------------------------------------------------------------------------

BASE_COINS_PER_SAND = 1
START_TANK_CAPACITY = 15
FIND_CHANCE_PER_SECOND = 0.02
BIG_TANK_MULTIPLIER = 2
FIND_BASE_VALUE = 3  # Münzen je 1 Sand/s Werkzeug-Grundrate und Sandfaktor x1
ZONE_FIND_CHANCE_FACTOR = {
    "duenenmeer": 1.0,
    "oase": 1.2,
    "canyon": 1.4,
    "salzsee": 1.6,
    "ruinenstadt": 2.0,
}

# ---------------------------------------------------------------------------
# Annahmen der Simulation
# ---------------------------------------------------------------------------

WALK_ONE_WAY_S = 5.0   # Sandfeld <-> Händler, etwa 80 Studs bei WalkSpeed 16
SELL_TIME_S = 0.0      # Verkauf ist ein Tastendruck am Stand
BUY_TIME_S = 0.0       # Knotenkauf im Menü wird nicht als Zeit gezählt
MAX_SIM_S = 3 * 3600

# Skilltree. Die ersten drei Knoten je Ast sind der Vorschlag,
# alles danach ist eine Platzhalter-Leiter nur für die Simulation.
# Sammeln-Knoten: Bonus in Prozent auf die Werkzeug-Grundrate (additiv).
# Tank-Knoten: neue Gesamtkapazität (vor dem Gamepass-Faktor).
COLLECT_CHAIN = [
    # (id, Preis, Art, Wert)
    ("sammeln_1", 15, "rate", 0.50),        # Vorschlag
    ("schaufel", 50, "tool", "schaufel"),   # Vorgabe
    ("sammeln_2", 120, "rate", 0.25),       # Vorschlag
    # ---- Platzhalter ab hier ----
    ("sammeln_3", 300, "rate", 0.25),
    ("eimerkette", 600, "tool", "eimerkette"),
    ("sammeln_4", 1_500, "rate", 0.25),
    ("sammeln_5", 3_500, "rate", 0.25),
    ("minibagger", 7_500, "tool", "minibagger"),
]
TANK_CHAIN = [
    ("tank_1", 20, "tank", 30),     # Vorschlag
    ("tank_2", 60, "tank", 60),     # Vorschlag
    ("tank_3", 250, "tank", 150),   # Vorschlag
    # ---- Platzhalter ab hier ----
    ("tank_4", 700, "tank", 400),
    ("tank_5", 1_800, "tank", 900),
    ("tank_6", 4_500, "tank", 1_800),
    ("tank_7", 11_000, "tank", 5_000),
]

MILESTONES = ["sammeln_1", "schaufel", "eimerkette", "minibagger"]

# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------


class Player:
    def __init__(self, coin_mult=1.0, big_tank=False, autodig=False,
                 start_coins=0.0, chains=None):
        self.coins = start_coins
        self.tool = "hand"
        self.rate_bonus = 0.0
        self.tank_cap = START_TANK_CAPACITY
        self.coin_mult = coin_mult
        self.big_tank = big_tank
        self.autodig = autodig
        chains = chains or (COLLECT_CHAIN, TANK_CHAIN)
        self.chains = [list(c) for c in chains]
        self.t = 0.0
        self.log = []          # (t, node_id, price)
        self.runs = []         # (zone, gather_s, run_s)

    @property
    def zone(self):
        best = "duenenmeer"
        owned = [t for t, _, _ in TOOLS if TOOL_RATE[t] <= TOOL_RATE[self.tool]]
        for z, _, req in ZONES:
            if req in owned:
                best = z
        return best

    @property
    def rate(self):
        return TOOL_RATE[self.tool] * (1 + self.rate_bonus)

    @property
    def capacity(self):
        return self.tank_cap * (BIG_TANK_MULTIPLIER if self.big_tank else 1)

    def frontier(self):
        return [c[0] for c in self.chains if c]

    def buy_greedy(self):
        """Kauft wiederholt den billigsten sichtbaren Knoten, solange Geld reicht."""
        while True:
            options = [n for n in self.frontier() if n[1] <= self.coins]
            if not options:
                return
            node = min(options, key=lambda n: n[1])
            for c in self.chains:
                if c and c[0] is node:
                    c.pop(0)
            self.coins -= node[1]
            _, price, kind, val = node
            if kind == "rate":
                self.rate_bonus += val
            elif kind == "tool":
                self.tool = val
            elif kind == "tank":
                self.tank_cap = val
            self.log.append((self.t, node[0], price))

    def do_run(self):
        """Ein Durchlauf ab dem Händler: hin, sammeln bis voll, zurück, verkaufen."""
        zone = self.zone
        cap = self.capacity
        walk = 2 * WALK_ONE_WAY_S
        tank = 0.0
        if self.autodig:
            # Annahme (obere Schranke): Auto-Dig sammelt schon auf dem Weg zum Feld.
            tank = min(cap, self.rate * WALK_ONE_WAY_S)
        gather = (cap - tank) / self.rate
        run = walk + gather + SELL_TIME_S
        self.t += run
        self.coins += cap * BASE_COINS_PER_SAND * SAND_FACTOR[zone] * self.coin_mult
        self.runs.append((zone, gather, run))


def simulate(**kw):
    p = Player(**kw)
    p.t = 0.0
    # Start am Spawn neben dem Sandfeld: der erste Weg hin entfällt.
    first = True
    while p.t < MAX_SIM_S and p.tool != "minibagger":
        if first:
            p.t -= WALK_ONE_WAY_S
            first = False
        p.do_run()
        p.buy_greedy()
    return p


def milestone_times(p):
    times = {}
    for t, node, _ in p.log:
        if node in MILESTONES and node not in times:
            times[node] = t
    return times


def fmt_t(s):
    if s is None:
        return "-"
    m, sec = divmod(int(round(s)), 60)
    return f"{m}:{sec:02d} min" if m else f"{sec} s"


# ---------------------------------------------------------------------------
# Fundstücke
# ---------------------------------------------------------------------------


def find_prob(gather_s, zone):
    p = FIND_CHANCE_PER_SECOND * ZONE_FIND_CHANCE_FACTOR[zone]
    return 1 - (1 - p) ** gather_s


def mc_runs_until_find(gather_s, zone, trials=200_000, seed=1):
    rng = random.Random(seed)
    p = FIND_CHANCE_PER_SECOND * ZONE_FIND_CHANCE_FACTOR[zone]
    whole = int(gather_s)
    rest = gather_s - whole
    p_rest = 1 - (1 - p) ** rest
    total = 0
    for _ in range(trials):
        n = 0
        while True:
            n += 1
            hit = any(rng.random() < p for _ in range(whole)) or rng.random() < p_rest
            if hit:
                break
        total += n
    return total / trials


def find_share_of_income(zone, tool, rate_bonus, value_scaling):
    """Anteil des Duplikat-Verkaufs am Gesamtertrag, wenn jeder Fund ein Duplikat ist."""
    rate = TOOL_RATE[tool] * (1 + rate_bonus)
    sand_income_per_s = rate * BASE_COINS_PER_SAND * SAND_FACTOR[zone]
    finds_per_s = FIND_CHANCE_PER_SECOND * ZONE_FIND_CHANCE_FACTOR[zone]
    if value_scaling == "zone_und_werkzeug":
        base = FIND_BASE_VALUE * SAND_FACTOR[zone] * TOOL_RATE[tool]
    else:  # nur Zone
        base = FIND_BASE_VALUE * SAND_FACTOR[zone]
    find_income_per_s = finds_per_s * EV_RARITY_FACTOR * base
    return find_income_per_s / (find_income_per_s + sand_income_per_s)


def gold_expected_crates_leg_plus():
    """Erwartete Goldkisten bis Legendär oder besser mit Pity bei 60."""
    q = 1 - GOLD_LEG_PLUS
    return (1 - q ** GOLD_PITY_LEG) / GOLD_LEG_PLUS


def mc_gold(trials=200_000, seed=7):
    rng = random.Random(seed)
    total = 0
    for _ in range(trials):
        n = 0
        while True:
            n += 1
            if n == GOLD_PITY_LEG or rng.random() < GOLD_LEG_PLUS:
                break
        total += n
    return total / trials


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------


def report_variant(name, p):
    ms = milestone_times(p)
    return (name, ms.get("sammeln_1"), ms.get("schaufel"),
            ms.get("eimerkette"), ms.get("minibagger"))


def main():
    global WALK_ONE_WAY_S, START_TANK_CAPACITY, BASE_COINS_PER_SAND
    print("=== Annahmen ===")
    print(f"Laufweg Feld<->Händler je Richtung: {WALK_ONE_WAY_S:.0f} s "
          f"(Hin und Rück {2 * WALK_ONE_WAY_S:.0f} s), Start am Feld")
    print("Strategie: nach jedem Verkauf den billigsten sichtbaren Knoten kaufen")
    print("Fundstücke bringen in der Zeit-Simulation keine Münzen (frühe Funde sind neu)")
    print()

    base = simulate()
    print("=== Basislauf: Kaufprotokoll ===")
    for t, node, price in base.log:
        print(f"  {fmt_t(t):>10}  {node:<12} {price:>7} Münzen")
    print()

    # Durchlauflängen pro Abschnitt
    print("=== Durchlauflänge (Sammeln + 10 s Weg) ===")
    by_zone = {}
    for zone, gather, run in base.runs:
        by_zone.setdefault(zone, []).append(run)
    for zone, runs in by_zone.items():
        inside = sum(1 for r in runs if 20 <= r <= 40) / len(runs)
        print(f"  {zone:<11} Läufe {len(runs):>3}  Median {sorted(runs)[len(runs)//2]:5.1f} s"
              f"  Min {min(runs):5.1f} s  Max {max(runs):5.1f} s  im Band 20-40 s: {inside:4.0%}")
    print()

    print("=== Zeit zwischen Käufen (Basislauf) ===")
    prev = 0.0
    gaps = []
    for t, node, _ in base.log:
        gaps.append((node, t - prev))
        prev = t
    longest = max(gaps, key=lambda g: g[1])
    print("  " + ", ".join(f"{n} +{g:.0f}s" for n, g in gaps))
    print(f"  Längste Pause: {longest[1]:.0f} s vor {longest[0]}")
    print()

    print("=== Meilensteine: Varianten ===")
    rows = [
        report_variant("Basis (Vorschlag)", base),
        report_variant("Gamepass Großer Tank x2", simulate(big_tank=True)),
        report_variant("Gamepass 2x Münzen", simulate(coin_mult=2.0)),
        report_variant("Auto-Dig (sammelt auf dem Hinweg)", simulate(autodig=True)),
        report_variant("2x Münzen + Großer Tank", simulate(coin_mult=2.0, big_tank=True)),
        report_variant("Daily Tag 1 = 100 Münzen beim Join", simulate(start_coins=100)),
    ]
    print(f"  {'Variante':<36}{'Upgrade 1':>11}{'Schaufel':>11}{'Eimerkette':>12}{'Mini-Bagger':>13}")
    for name, a, b, c, d in rows:
        print(f"  {name:<36}{fmt_t(a):>11}{fmt_t(b):>11}{fmt_t(c):>12}{fmt_t(d):>13}")
    print()

    # Empfindlichkeit: Laufweg
    print("=== Empfindlichkeit: Laufweg je Richtung ===")
    saved = WALK_ONE_WAY_S
    for w in (3.0, 5.0, 8.0):
        WALK_ONE_WAY_S = w
        name, a, b, c, d = report_variant(f"{w:.0f} s", simulate())
        print(f"  Weg {name:<5} Upgrade 1 {fmt_t(a):>7}  Schaufel {fmt_t(b):>9}"
              f"  Eimerkette {fmt_t(c):>9}  Mini-Bagger {fmt_t(d):>9}")
    WALK_ONE_WAY_S = saved
    print()

    # Empfindlichkeit: Starttank
    print("=== Empfindlichkeit: Starttank und Münzen pro Sand ===")
    s_tank, s_cps = START_TANK_CAPACITY, BASE_COINS_PER_SAND
    for tank, cps in ((10, 1), (15, 1), (20, 1), (15, 2)):
        START_TANK_CAPACITY, BASE_COINS_PER_SAND = tank, cps
        name, a, b, c, d = report_variant("", simulate())
        print(f"  Tank {tank:>2}, {cps} Münze/Sand: Upgrade 1 {fmt_t(a):>6}  Schaufel {fmt_t(b):>9}"
              f"  Eimerkette {fmt_t(c):>9}  Mini-Bagger {fmt_t(d):>9}")
    START_TANK_CAPACITY, BASE_COINS_PER_SAND = s_tank, s_cps
    print()

    print("=== Fundstücke ===")
    print(f"  Erwarteter Wertfaktor je Fund (gewichtete Seltenheit): x{EV_RARITY_FACTOR:.2f}")
    early = [(z, g) for z, g, _ in base.runs if z == "duenenmeer"]
    first_runs = early[:6]
    gathered_2min = 0.0
    t = -WALK_ONE_WAY_S
    for z, g, r in base.runs:
        if t + r > 120:
            break
        gathered_2min += g
        t += r
    p_any_2min = 1 - (1 - FIND_CHANCE_PER_SECOND) ** gathered_2min
    print(f"  Sammelsekunden in den ersten 2 Minuten: {gathered_2min:.0f} s, "
          f"P(mindestens ein Fund) = {p_any_2min:.0%}")
    for gather in (15, 20, 25):
        print(f"  Dünenmeer, {gather} s Sammeln pro Lauf: P(Fund im Lauf) = "
              f"{find_prob(gather, 'duenenmeer'):.0%}, im Mittel alle "
              f"{1 / find_prob(gather, 'duenenmeer'):.1f} Läufe")
    mc = mc_runs_until_find(20, "duenenmeer", trials=50_000)
    print(f"  Monte Carlo (20 s Sammeln, 50.000 Versuche): {mc:.2f} Läufe bis zum ersten Fund")
    for z, _, _ in ZONES:
        print(f"  {z:<11} Fundchance/s {FIND_CHANCE_PER_SECOND * ZONE_FIND_CHANCE_FACTOR[z]:.3f}"
              f"  -> bei 20 s Sammeln alle {1 / find_prob(20, z):.1f} Läufe")
    # Erwartete Sammelzeit bis zum ersten Fund je Seltenheit
    print("  Erwartete Sammelzeit bis zum ersten Fund einer Seltenheit (Dünenmeer, ohne Glück):")
    for rid, share, _ in RARITIES:
        secs = 1 / (FIND_CHANCE_PER_SECOND * share)
        print(f"    {rid:<14} {secs / 60:8.1f} min Sammeln")
    print()

    print("=== Duplikat-Verkauf: Anteil am Ertrag (alle Funde Duplikate) ===")
    cases = [("duenenmeer", "hand", 0.5), ("duenenmeer", "schaufel", 0.75),
             ("oase", "eimerkette", 1.0), ("canyon", "minibagger", 1.5),
             ("salzsee", "saugroboter", 2.0), ("ruinenstadt", "hand", 0.0)]
    print(f"  {'Zone':<12}{'Werkzeug':<13}{'Bonus':>6}  {'nur Zone':>9}  {'Zone x Werkzeug':>16}"
          f"  {'Gewöhnlich (Z x W)':>19}")
    for zone, tool, bonus in cases:
        a = find_share_of_income(zone, tool, bonus, "nur_zone")
        b = find_share_of_income(zone, tool, bonus, "zone_und_werkzeug")
        common = FIND_BASE_VALUE * SAND_FACTOR[zone] * TOOL_RATE[tool]
        print(f"  {zone:<12}{tool:<13}{bonus:>6.0%}  {a:>9.2%}  {b:>16.1%}  {common:>16,} M")
    print()

    print("=== Ausblick: Werkzeugpreis in Sekunden Grundertrag (Vorgänger, beste Zone) ===")
    zone_for = {"hand": "duenenmeer", "schaufel": "duenenmeer", "eimerkette": "oase",
                "minibagger": "canyon", "saugroboter": "salzsee"}
    for (prev, prate, _), (tool, _, price) in zip(TOOLS, TOOLS[1:]):
        z = zone_for[prev]
        secs = price / (prate * SAND_FACTOR[z] * BASE_COINS_PER_SAND)
        print(f"  {tool:<14} {price:>10,} Münzen = {secs:6.1f} s Grundertrag mit {prev} in {z}")
    print()

    print("=== Kontrolle Goldkiste (Konzept: etwa 20 Kisten, 8.000 Gems) ===")
    e = gold_expected_crates_leg_plus()
    print(f"  Erwartete Kisten bis Legendär+: {e:.2f} (analytisch), "
          f"{mc_gold():.2f} (Monte Carlo) -> {e * GOLD_PRICE_GEMS:,.0f} Gems einzeln, "
          f"{e * GOLD_PRICE_GEMS * 10 / 11:,.0f} Gems im 10er-Paket")
    print()

    print("=== Finale Werte ===")
    print(f"  baseCoinsPerSand      = {BASE_COINS_PER_SAND}")
    print(f"  startTankCapacity     = {START_TANK_CAPACITY}")
    print(f"  findChancePerSecond   = {FIND_CHANCE_PER_SECOND}")
    print(f"  bigTankMultiplier     = {BIG_TANK_MULTIPLIER}")
    print(f"  findBaseValue         = {FIND_BASE_VALUE}  (x Sandfaktor x Werkzeug-Grundrate x Wertfaktor)")
    print(f"  zoneFindChanceFactor  = {ZONE_FIND_CHANCE_FACTOR}")


if __name__ == "__main__":
    main()
