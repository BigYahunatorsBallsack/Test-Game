#!/usr/bin/env python3
"""Paket 4.2: Kisten-Quoten mit Pity, exakte Rechnung und Gegenprobe.

Aufruf: python3 docs/balance/crates_4_2.py   (nur Standardbibliothek, Ausgabe reproduzierbar)

Quelle der Zahlen: src/shared/Data/Crates.luau (Stand 19.11.2026), Quoten in
Hundertstel-Prozent (10000 = 100 %). Pity-Regeln laut Plan, Abschnitt
"Quoten, Pity und Zufall":
  - Zähler sinceEpic (e) und sinceLegendary (l) zählen Öffnungen ohne
    Episch-oder-besser bzw. Legendär-oder-besser.
  - l == 59: Wurf nur zwischen Legendär und Mythisch (450:50).
  - sonst e == 14: Wurf nur zwischen Episch, Legendär, Mythisch (1500:450:50).
  - Greifen beide, gewinnt die Legendär-Garantie.
  - Legendär/Mythisch setzt e und l auf 0, Episch nur e; sonst beide +1.
Die Rechnung ist exakt (fractions.Fraction): Markov-Kette über (e, l), die bei
jedem Legendär-oder-besser-Treffer nach (0, 0) zurückspringt. Daraus folgen
über Erneuerungstheorie die stationären Raten (Erwartung je Zyklus durch
mittlere Zykluslänge). Die Simulation ist nur Gegenprobe.
"""
from __future__ import annotations

import math
import random
from fractions import Fraction as F
from functools import lru_cache

# ---------------------------------------------------------------- Daten
RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
NAMES_DE = {
    "common": "Gewöhnlich", "uncommon": "Ungewöhnlich", "rare": "Selten",
    "epic": "Episch", "legendary": "Legendär", "mythic": "Mythisch",
}
ODDS = {  # Hundertstel-Prozent, aus Crates.luau
    "wood": {"common": 6000, "uncommon": 3000, "rare": 900, "epic": 100, "legendary": 0, "mythic": 0},
    "iron": {"common": 3500, "uncommon": 4000, "rare": 2000, "epic": 500, "legendary": 0, "mythic": 0},
    "gold": {"common": 0, "uncommon": 4000, "rare": 4000, "epic": 1500, "legendary": 450, "mythic": 50},
}
PRICE = {"wood": (25000, "Münzen"), "iron": (100, "Gems"), "gold": (400, "Gems")}
PITY_EPIC = 15        # Episch oder besser spätestens bei dieser Öffnung
PITY_LEGENDARY = 60   # Legendär oder besser spätestens bei dieser Öffnung
BUNDLE_BUY, BUNDLE_GET = 10, 11
EPIC_PLUS = ("epic", "legendary", "mythic")
LEG_PLUS = ("legendary", "mythic")

SIM_OPENINGS = 1_000_000
SIM_SEED = 4200
SIM_BATCHES = 100

CONCEPT_OPENINGS = 20     # Konzept: "im Schnitt nach etwa 20 Goldkisten"
CONCEPT_GEMS = 8000       # Konzept: "rund 8.000 Gems"

TABLE = ODDS["gold"]
TOTAL = sum(TABLE.values())
assert TOTAL == 10000


# ---------------------------------------------------------------- Regeln
def mode_of(e: int, l: int, pity_e: int | None, pity_l: int | None) -> str:
    """'L' = Legendär-Garantie, 'E' = Episch-Garantie, 'N' = normaler Wurf."""
    if pity_l is not None and l >= pity_l - 1:
        return "L"
    if pity_e is not None and e >= pity_e - 1:
        return "E"
    return "N"


def outcomes(mode: str) -> list[tuple[str, F]]:
    allowed = {"L": LEG_PLUS, "E": EPIC_PLUS, "N": tuple(RARITIES)}[mode]
    tot = sum(TABLE[r] for r in allowed)
    return [(r, F(TABLE[r], tot)) for r in allowed if TABLE[r] > 0]


OUT = {m: outcomes(m) for m in "NEL"}


def next_state(e: int, l: int, rarity: str, track_l: bool) -> tuple[int, int]:
    if rarity in LEG_PLUS:
        return 0, 0
    if rarity == "epic":
        return 0, (l + 1 if track_l else 0)
    return e + 1, (l + 1 if track_l else 0)


# ---------------------------------------------------------------- exakt: Zyklus
def cycle_stats(pity_e: int | None, pity_l: int | None):
    """Vorwärts-Propagation eines Zyklus ab (0, 0) bis zum Erneuerungsereignis.

    Erneuerung: Legendär-oder-besser, wenn die Legendär-Pity aktiv ist (dann
    endet jeder Zyklus nach höchstens pity_l Öffnungen), sonst Episch-oder-besser
    (nur Episch-Pity, Zustand nur e). Alles exakt.
    """
    track_l = pity_l is not None
    renew = LEG_PLUS if track_l else EPIC_PLUS
    mass = {(0, 0): F(1)}
    counts = {(r, m): F(0) for r in RARITIES for m in "NEL"}
    visits: dict[tuple[int, int], F] = {}
    p_len: dict[int, F] = {}
    k = 0
    while mass:
        k += 1
        new: dict[tuple[int, int], F] = {}
        for (e, l), p in mass.items():
            visits[(e, l)] = visits.get((e, l), F(0)) + p
            m = mode_of(e, l, pity_e, pity_l)
            for r, q in OUT[m]:
                pq = p * q
                counts[(r, m)] += pq
                if r in renew:
                    p_len[k] = p_len.get(k, F(0)) + pq
                else:
                    s = next_state(e, l, r, track_l)
                    new[s] = new.get(s, F(0)) + pq
        mass = new
        assert k <= 200
    et = sum(F(n) * p for n, p in p_len.items())
    et2 = sum(F(n * n) * p for n, p in p_len.items())
    assert sum(p_len.values()) == 1
    assert sum(counts.values()) == et
    return {"ET": et, "ET2": et2, "counts": counts, "visits": visits, "p_len": p_len}


def rates_from(cs) -> dict[str, F]:
    return {r: sum(cs["counts"][(r, m)] for m in "NEL") / cs["ET"] for r in RARITIES}


# ---------------------------------------------------------------- exakt: Wartezeiten
@lru_cache(maxsize=None)
def h_leg(e: int, l: int) -> F:
    """Erwartete Öffnungen bis Legendär-oder-besser ab Zustand (e, l), Treffer mitgezählt."""
    m = mode_of(e, l, PITY_EPIC, PITY_LEGENDARY)
    v = F(1)
    for r, q in OUT[m]:
        if r not in LEG_PLUS:
            v += q * h_leg(*next_state(e, l, r, True))
    return v


@lru_cache(maxsize=None)
def h_epic(e: int, l: int) -> F:
    """Erwartete Öffnungen bis Episch-oder-besser ab Zustand (e, l), Treffer mitgezählt."""
    m = mode_of(e, l, PITY_EPIC, PITY_LEGENDARY)
    v = F(1)
    for r, q in OUT[m]:
        if r not in EPIC_PLUS:
            v += q * h_epic(*next_state(e, l, r, True))
    return v


# ---------------------------------------------------------------- Simulation
def simulate(n: int, seed: int, batches: int):
    """Spiegelt die Server-Logik: Ganzzahl-Wurf über die Hundertstel-Prozent-Gewichte."""
    rng = random.Random(seed)
    cum = {}
    for m in "NEL":
        allowed = {"L": LEG_PLUS, "E": EPIC_PLUS, "N": tuple(RARITIES)}[m]
        acc, lst = 0, []
        for r in allowed:
            if TABLE[r] > 0:
                acc += TABLE[r]
                lst.append((acc, r))
        cum[m] = (acc, lst)
    e = l = 0
    counts = {r: 0 for r in RARITIES}
    mode_counts = {m: 0 for m in "NEL"}
    hit_by_mode = {("L+", m): 0 for m in "NEL"} | {("E+", m): 0 for m in "NEL"}
    leg_gaps, epic_gaps, fresh_epic = [], [], []
    since_leg_hit = since_epic_hit = 0
    fresh_epic_running = True
    fresh_epic_count = 0
    bsize = n // batches
    batch_counts = [{r: 0 for r in RARITIES} for _ in range(batches)]
    for i in range(n):
        m = "L" if l >= PITY_LEGENDARY - 1 else ("E" if e >= PITY_EPIC - 1 else "N")
        tot, lst = cum[m]
        x = rng.randint(1, tot)
        for c, r in lst:
            if x <= c:
                break
        counts[r] += 1
        mode_counts[m] += 1
        batch_counts[i // bsize][r] += 1
        since_leg_hit += 1
        since_epic_hit += 1
        if fresh_epic_running:
            fresh_epic_count += 1
        if r in EPIC_PLUS:
            hit_by_mode[("E+", m)] += 1
            epic_gaps.append(since_epic_hit)
            since_epic_hit = 0
            if fresh_epic_running:
                fresh_epic.append(fresh_epic_count)
                fresh_epic_running = False
        if r in LEG_PLUS:
            hit_by_mode[("L+", m)] += 1
            leg_gaps.append(since_leg_hit)
            since_leg_hit = 0
            e = l = 0
            fresh_epic_running, fresh_epic_count = True, 0
        elif r == "epic":
            e, l = 0, l + 1
        else:
            e, l = e + 1, l + 1
    return {
        "counts": counts, "mode_counts": mode_counts, "hit_by_mode": hit_by_mode,
        "leg_gaps": leg_gaps, "epic_gaps": epic_gaps, "fresh_epic": fresh_epic,
        "batch_counts": batch_counts, "bsize": bsize,
    }


# ---------------------------------------------------------------- Ausgabe-Helfer
def pct(x, d=4) -> str:
    return f"{float(x) * 100:.{d}f} %".replace(".", ",")


def num(x, d=4) -> str:
    return f"{float(x):,.{d}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def main() -> None:
    print("Paket 4.2: Kisten-Quoten mit Pity (exakt) und Gegenprobe")
    print(f"Pity Gold: Episch+ spätestens bei {PITY_EPIC}., Legendär+ spätestens bei {PITY_LEGENDARY}. Öffnung\n")

    # ---------- (1) Hauptkette
    cs = cycle_stats(PITY_EPIC, PITY_LEGENDARY)
    ET, ET2 = cs["ET"], cs["ET2"]
    rates = rates_from(cs)
    assert sum(rates.values()) == 1
    print("(1) Effektive Wahrscheinlichkeit je Öffnung, Goldkiste mit Pity (stationär)")
    print(f"{'Seltenheit':<13}{'Tabelle':>12}{'mit Pity':>14}{'Faktor':>9}")
    for r in RARITIES:
        base = F(TABLE[r], TOTAL)
        fac = "-" if base == 0 else num(rates[r] / base, 4)
        print(f"{NAMES_DE[r]:<13}{pct(base, 2):>12}{pct(rates[r], 4):>14}{fac:>9}")
    pe = sum(rates[r] for r in EPIC_PLUS)
    pl = sum(rates[r] for r in LEG_PLUS)
    print(f"{'Episch+':<13}{pct(F(2000, 10000), 2):>12}{pct(pe, 4):>14}{num(pe / F(2000, 10000), 4):>9}")
    print(f"{'Legendär+':<13}{pct(F(500, 10000), 2):>12}{pct(pl, 4):>14}{num(pl / F(500, 10000), 4):>9}")
    print("exakte Werte, 12 Stellen (aus den Brüchen):")
    for r in RARITIES:
        print(f"  {r:<10} = {float(rates[r]):.12f}")
    print()

    # ---------- (2) Wartezeiten
    pi = {s: v / ET for s, v in cs["visits"].items()}
    assert sum(pi.values()) == 1
    resid_leg = sum(p * h_leg(*s) for s, p in pi.items())
    resid_epic = sum(p * h_epic(*s) for s, p in pi.items())
    assert h_leg(0, 0) == ET
    assert resid_leg == (ET2 + ET) / (2 * ET)  # Erneuerungs-Identität E[T(T+1)]/(2E[T])
    print("(2) Erwartete Öffnungen bis zum Treffer (Treffer mitgezählt)")
    print(f"  Legendär+ ab frischem Zähler (0,0)       : {num(ET, 6)}")
    print(f"  Legendär+ mittlerer Abstand stationär    : {num(1 / pl, 6)} (= ab frisch, Erneuerung)")
    print(f"  Legendär+ Restwartezeit, zufälliger Zeitpunkt: {num(resid_leg, 6)}")
    var = ET2 - ET * ET
    print(f"  Streuung der Öffnungen bis Legendär+ (SD) : {num(math.sqrt(var), 4)}")
    print(f"  Episch+ ab frischem Zähler (0,0)         : {num(h_epic(0, 0), 6)}")
    print(f"  Episch+ mittlerer Abstand stationär      : {num(1 / pe, 6)}")
    print(f"  Episch+ Restwartezeit, zufälliger Zeitpunkt: {num(resid_epic, 6)}")
    print(f"  Mythisch mittlerer Abstand (= 10 x Legendär+, L:M ist in jedem Wurf 9:1): {num(1 / rates['mythic'], 4)}")
    cdf, acc = {}, F(0)
    for k in sorted(cs["p_len"]):
        acc += cs["p_len"][k]
        cdf[k] = acc
    print("  Verteilung der Öffnungen bis Legendär+ ab frisch:")
    for q in (F(1, 2), F(3, 4), F(9, 10), F(95, 100), F(99, 100)):
        k = min(k for k, c in cdf.items() if c >= q)
        print(f"    {pct(q, 0):>6}-Quantil: {k:>2} Öffnungen = {k * 400:>6} Gems")
    print(f"    P(Treffer erst durch harte Pity bei {PITY_LEGENDARY}) = {pct(cs['p_len'][PITY_LEGENDARY], 4)}")
    print(f"    P(Treffer innerhalb der ersten {PITY_EPIC} Öffnungen) = {pct(cdf[PITY_EPIC], 4)}")
    print()

    # ---------- (3) Gems
    gems = ET * 400
    gems_bundle = ET * F(400 * BUNDLE_BUY, BUNDLE_GET)
    print("(3) Erwartete Gems bis Legendär+")
    print(f"  Einzelkauf (400 Gems/Öffnung)            : {num(gems, 1)} Gems")
    print(f"  nur 10er-Pakete (4000/11 Gems/Öffnung)   : {num(gems_bundle, 1)} Gems (rechnerisch, ohne Rundung auf ganze Pakete)")
    print(f"  Konzept: {CONCEPT_OPENINGS} Kisten, {CONCEPT_GEMS} Gems -> Abweichung {num(ET - CONCEPT_OPENINGS, 4)} Kisten "
          f"({pct(ET / CONCEPT_OPENINGS - 1, 2)}), {num(gems - CONCEPT_GEMS, 1)} Gems")
    print(f"  Schlimmster Fall bis Legendär+: {PITY_LEGENDARY} Öffnungen = {PITY_LEGENDARY * 400} Gems einzeln, "
          f"5 Pakete + 5 einzeln = {5 * 4000 + 5 * 400} Gems")
    print(f"  Schlimmster Fall bis Episch+  : {PITY_EPIC} Öffnungen = {PITY_EPIC * 400} Gems einzeln, "
          f"1 Paket + 4 einzeln = {4000 + 4 * 400} Gems")
    print()

    # ---------- (4) Pity-Anteile
    c = cs["counts"]
    open_mode = {m: sum(c[(r, m)] for r in RARITIES) / ET for m in "NEL"}
    leg_from = {m: sum(c[(r, m)] for r in LEG_PLUS) / ET for m in "NEL"}
    epic_from = {m: sum(c[(r, m)] for r in EPIC_PLUS) / ET for m in "NEL"}
    print("(4) Pity-Anteile (stationär)")
    print(f"  Öffnungen mit aktiver Legendär-Garantie : {pct(open_mode['L'], 4)}")
    print(f"  Öffnungen mit aktiver Episch-Garantie   : {pct(open_mode['E'], 4)}")
    print(f"  Öffnungen mit irgendeiner Garantie      : {pct(open_mode['L'] + open_mode['E'], 4)}")
    print(f"  Legendär+-Treffer aus Legendär-Garantie : {pct(leg_from['L'] / pl, 4)}")
    print(f"  Legendär+-Treffer aus Episch-Garantie   : {pct(leg_from['E'] / pl, 4)}")
    print(f"  Legendär+-Treffer aus normalem Wurf     : {pct(leg_from['N'] / pl, 4)}")
    print(f"  Episch+-Treffer aus Episch-Garantie     : {pct(epic_from['E'] / pe, 4)}")
    print(f"  Episch+-Treffer aus Legendär-Garantie   : {pct(epic_from['L'] / pe, 4)}")
    print(f"  Episch+-Treffer aus normalem Wurf       : {pct(epic_from['N'] / pe, 4)}")
    # "netto": Treffer, die ohne Garantie (normaler Wurf in derselben Öffnung) ausgeblieben wären
    net_l = open_mode["L"] * F(9500, 10000) + open_mode["E"] * (F(500, 2000) - F(500, 10000))
    net_e = open_mode["E"] * F(8000, 10000) + open_mode["L"] * F(8000, 10000)
    print(f"  netto durch Pity erzeugte Legendär+ je Öffnung: {pct(net_l, 4)} "
          f"(Anteil an allen Legendär+: {pct(net_l / pl, 2)})")
    print(f"  netto durch Pity erzeugte Episch+ je Öffnung  : {pct(net_e, 4)} "
          f"(Anteil an allen Episch+: {pct(net_e / pe, 2)})")
    print()

    # ---------- Varianten: welche Pity bewirkt wie viel
    print("Zerlegung: Wirkung der beiden Garantien")
    print(f"{'Variante':<26}{'P(Episch+)':>12}{'P(Legendär+)':>14}{'Öffn. bis L+':>14}{'Gems bis L+':>13}")
    rows = [("ohne Pity (reine Tabelle)", F(2000, 10000), F(500, 10000))]
    v = cycle_stats(None, PITY_LEGENDARY)
    rv = rates_from(v)
    rows.append(("nur Legendär-Pity (60)", sum(rv[r] for r in EPIC_PLUS), sum(rv[r] for r in LEG_PLUS)))
    v = cycle_stats(PITY_EPIC, None)
    rv = rates_from(v)
    rows.append(("nur Episch-Pity (15)", sum(rv[r] for r in EPIC_PLUS), sum(rv[r] for r in LEG_PLUS)))
    rows.append(("beide (Ist)", pe, pl))
    for name, a, b in rows:
        print(f"{name:<26}{pct(a, 3):>12}{pct(b, 3):>14}{num(1 / b, 4):>14}{num(400 / b, 0):>13}")
    print("  Hinweis: Jeder Episch+-Treffer ist mit 25 % Legendär+ (normal 500/2000, Garantie 500/2000),")
    print("  darum hebt die Episch-Garantie die Legendär-Rate fast im selben Verhältnis wie die Episch-Rate.")
    print()

    # ---------- (5) Holz und Eisen
    print("(5) Holz- und Eisenkiste (keine Pity, reine Tabelle)")
    for cid in ("wood", "iron"):
        t = ODDS[cid]
        tot = sum(t.values())
        price, cur = PRICE[cid]
        p_rare = F(sum(t[r] for r in ("rare", "epic", "legendary", "mythic")), tot)
        p_epic = F(sum(t[r] for r in EPIC_PLUS), tot)
        print(f"  {cid}: " + ", ".join(f"{NAMES_DE[r]} {pct(F(t[r], tot), 0)}" for r in RARITIES))
        print(f"    Selten+ {pct(p_rare, 0)}: im Schnitt {num(1 / p_rare, 1)} Öffnungen = {num(price / p_rare, 0)} {cur}")
        print(f"    Episch+ {pct(p_epic, 0)}: im Schnitt {num(1 / p_epic, 1)} Öffnungen = {num(price / p_epic, 0)} {cur}")
        print("    Legendär+: 0 % (nicht erreichbar)")
        for k in (10, 50, 100):
            print(f"    P(mind. ein Episch in {k} Öffnungen) = {pct(1 - (1 - p_epic) ** k, 1)}")
    print()

    # ---------- Simulation
    sim = simulate(SIM_OPENINGS, SIM_SEED, SIM_BATCHES)
    n = SIM_OPENINGS
    print(f"Gegenprobe: Simulation mit {num(n, 0)} Öffnungen, Seed {SIM_SEED}, Standardfehler aus {SIM_BATCHES} Blöcken")
    print(f"{'Größe':<28}{'exakt':>13}{'Simulation':>13}{'Abw.':>11}{'z':>7}")

    def batch_se(keys):
        vals = [sum(b[r] for r in keys) / sim["bsize"] for b in sim["batch_counts"]]
        mu = sum(vals) / len(vals)
        sd = math.sqrt(sum((x - mu) ** 2 for x in vals) / (len(vals) - 1))
        return sd / math.sqrt(len(vals))

    def row(label, exact, simv, se):
        diff = f"{(simv - float(exact)) * 100:+.4f}".replace(".", ",")
        z = "-" if se <= 0 else f"{(simv - float(exact)) / se:+.2f}".replace(".", ",")
        print(f"{label:<28}{pct(exact, 4):>13}{pct(simv, 4):>13}{diff:>11}{z:>7}")

    maxz = 0.0
    for r in RARITIES[1:]:
        s = sim["counts"][r] / n
        se = batch_se((r,))
        row(NAMES_DE[r], rates[r], s, se)
        maxz = max(maxz, abs((s - float(rates[r])) / se))
    for label, keys, ex in (("Episch+", EPIC_PLUS, pe), ("Legendär+", LEG_PLUS, pl)):
        s = sum(sim["counts"][r] for r in keys) / n
        row(label, ex, s, batch_se(keys))
    for m, label in (("L", "Öffn. mit Legendär-Garantie"), ("E", "Öffn. mit Episch-Garantie")):
        row(label, open_mode[m], sim["mode_counts"][m] / n, 0)
    g = sim["leg_gaps"]
    mg = sum(g) / len(g)
    seg = math.sqrt(sum((x - mg) ** 2 for x in g) / (len(g) - 1)) / math.sqrt(len(g))
    print(f"  Öffnungen bis Legendär+ (Mittel über {num(len(g), 0)} Zyklen): exakt {num(ET, 4)}, Simulation {num(mg, 4)}, "
          f"Abw. {num(mg - float(ET), 4)} (z = {num((mg - float(ET)) / seg, 2)})")
    fe = sim["fresh_epic"]
    mfe = sum(fe) / len(fe)
    print(f"  Öffnungen bis Episch+ ab frisch: exakt {num(h_epic(0, 0), 4)}, Simulation {num(mfe, 4)}")
    eg = sim["epic_gaps"]
    print(f"  mittlerer Episch+-Abstand: exakt {num(1 / pe, 4)}, Simulation {num(sum(eg) / len(eg), 4)}")
    print(f"  längster Abstand Legendär+: {max(g)} (Grenze {PITY_LEGENDARY}), Episch+: {max(eg)} (Grenze {PITY_EPIC})")
    print(f"  größte |z| der Einzel-Seltenheiten: {num(maxz, 2)}")
    print()

    # ---------- Sollwerte für Lune
    # Standardabweichung der Legendär+-Anzahl in N Öffnungen (Erneuerungs-ZGS): sqrt(N * Var(T) / E[T]^3)
    print("Sollwerte für einen Lune-Test (Goldkiste mit Pity)")
    for r in RARITIES:
        print(f"  {r:<10} {float(rates[r]):.6f}")
    print(f"  epicPlus   {float(pe):.6f}")
    print(f"  legPlus    {float(pl):.6f}")
    print(f"  openingsToLegendaryFresh {float(ET):.4f}")
    print(f"  openingsToEpicFresh      {float(h_epic(0, 0)):.4f}")
    for N in (100_000, 1_000_000):
        sd_leg = math.sqrt(N * float(var) / float(ET) ** 3) / N
        print(f"  N = {num(N, 0):>9}: SD(Legendär+-Rate) ~ {num(sd_leg * 100, 4)} Prozentpunkte")


if __name__ == "__main__":
    main()
