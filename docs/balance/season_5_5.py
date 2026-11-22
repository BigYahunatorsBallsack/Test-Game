#!/usr/bin/env python3
"""Dune Baron, Paket 5.5: Saison 1 (Event-Zone "Saison-Sand", Saison-Punkte, Saison-Pass, Event-Kiste).

Bericht: docs/balance/season_5_5.md. Ändert nichts unter src/ oder tests/.

Fragen
  1. Preisfaktor des Event-Sands (Zone ab collect_tool_2): Wirkung auf Lauf 1 und auf 10 Sturm-Läufe,
     Ertrag in der Event-Zone gegenüber der besten festen Zone je Phase.
  2. secondsPerPoint: Punkte je Gang, Anteil der Grabzeit an der Zeit in der Zone (Weg, Großer Tank,
     Auto-Dig).
  3. Pass mit 20 Stufen: Punktestände, Gratis- und Premium-Spur.
  4. Ziele: Gelegenheitsspieler (30 min Graben je Tag, 28 Tage) etwa zwei Drittel der Spur, Vielspieler
     (2 h je Tag) die ganze Spur vor Ende von Woche 3; Premium-Gems deutlich unter dem Gem-Wert von
     399 Robux; Gratis-Spur bescheiden. Monte Carlo mit ausgelassenen Tagen und schwankender Spielzeit.
  5. Ersatz-Gems bei Doppelkauf, Abholfrist.
  6. Event-Kiste: Quoten wie Gold, Pool je Seltenheit gefüllt, Kosten bis Legendär+ und bis zu einem
     bestimmten Item (Pity wie Logic/CrateRoll).

Modell: Baum, Schleife, Funde, Kristalle aus sandstorm_2_7.py (und damit 2.1 und 2.6), Datenabgleich
aus passes_4_4.py, Pity-Kette aus directshop_4_6.py (alles importiert, nichts kopiert).
Die Event-Zone hat in diesem Modell keine Funde (Testfall 5.5a: die Sammlung bleibt bei den fünf
festen Zonen); ein Spieler, der nur Münzen will, gräbt immer in der Zone mit dem höchsten Sandfaktor.

Nur Standardbibliothek, feste Seeds ab 5500. Aufruf: python3 docs/balance/season_5_5.py (etwa 10 s).
"""

import math
import os
import random
import re
import sys
from fractions import Fraction as F

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sandstorm_2_7 as ss  # noqa: E402
import passes_4_4 as pp  # noqa: E402
import directshop_4_6 as ds  # noqa: E402

st = ss.st
ROOT = os.path.dirname(os.path.dirname(HERE))
SEED = 5500

# ---------------------------------------------------------------------------
# Vorschlag (alles, was in Data/SandTypes, Data/Zones, Data/SeasonPass, Economy.seasonPass gehört)
# ---------------------------------------------------------------------------

EVENT_FACTOR = 5                 # SandTypes "season".priceFactor (Platzhalter in den Daten: 20)
EVENT_NODE = "collect_tool_2"    # Zones "season_camp".requires
SECONDS_PER_POINT = 10           # Economy.seasonPass.secondsPerPoint
DUPLICATE_GEMS = 850             # Economy.seasonPass.duplicateGems
CLAIM_DAYS = 3                   # Economy.seasonPass.claimGraceDays
PREMIUM_GEMS_MAX_SHARE = 0.50    # Vorschlag Economy.seasonPass.premiumGemsMaxPercent = 50 (DataCheck)

# Zuwachs je Stufe (Punkte); Punktestand = laufende Summe. Kurve etwa 20,5 * n^1,4, gerundet.
INCREMENTS = [30, 60, 90, 140, 190, 250, 310, 370, 440, 510,
              580, 660, 740, 830, 910, 1000, 1090, 1190, 1290, 1320]
THRESHOLDS = [sum(INCREMENTS[:i + 1]) for i in range(len(INCREMENTS))]

# Belohnungen je Stufe: (Art, Wert). coinBoost/luck in Sekunden, gems als ganze Zahl, item als ID.
M = 60
FREE = [
    ("coinBoost", 5 * M), ("gems", 5), ("luck", 10 * M), ("coinBoost", 10 * M), ("gems", 5),
    ("luck", 10 * M), ("coinBoost", 10 * M), ("gems", 10), ("luck", 10 * M), ("coinBoost", 10 * M),
    ("gems", 10), ("luck", 15 * M), ("coinBoost", 15 * M), ("gems", 10), ("luck", 15 * M),
    ("coinBoost", 15 * M), ("gems", 15), ("luck", 15 * M), ("coinBoost", 15 * M), ("gems", 20),
]
PREMIUM = [
    ("item", "skin_rare_4"), ("gems", 25), ("coinBoost", 30 * M), ("gems", 30), ("luck", 30 * M),
    ("gems", 35), ("coinBoost", 30 * M), ("gems", 40), ("luck", 30 * M), ("item", "companion_epic_3"),
    ("gems", 50), ("coinBoost", 30 * M), ("gems", 70), ("luck", 30 * M), ("coinBoost", 30 * M),
    ("gems", 60), ("luck", 30 * M), ("gems", 90), ("luck", 60 * M), ("item", "toolVariant_epic_3"),
]
# Pass-Items: nur über den Pass, in keiner Kiste (crates = {}), effectBp wie Event-Pool gleicher Seltenheit.
PASS_ITEMS = {
    "skin_rare_4": ("skin", "Dünenpionier", "rare", 1000),
    "companion_epic_3": ("companion", "Saison-Karakal", "epic", 1400),
    "toolVariant_epic_3": ("toolVariant", "Baronsschaufel", "epic", 1400),
}

# Spielertypen (Minuten echtes Graben in der Event-Zone je Tag)
CASUAL_MIN = 30
HEAVY_MIN = 120
SEASON_DAYS = 28
FACTORS = [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 40]
FIXED_FACTORS = {"dunes": 1, "oasis": 3, "canyon": 10, "salt_lake": 40, "ruins": 150}
ZONE_DE = {"dunes": "Dünenmeer", "oasis": "Oase", "canyon": "Canyon", "salt_lake": "Salzsee",
           "ruins": "Ruinenstadt", "event": "Event-Zone"}


# ---------------------------------------------------------------------------
# 0. Daten lesen und abgleichen
# ---------------------------------------------------------------------------

def luau(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def load_data():
    sand = {m.group(1): float(m.group(2)) for m in
            re.finditer(r'id = "(\w+)",[^\n]*?priceFactor = ([\d.]+)', luau("src/shared/Data/SandTypes.luau"))}
    zones = {}
    for blk in re.findall(r"\{(.*?)\n    \}", luau("src/shared/Data/Zones.luau"), re.S):
        i = re.search(r'id = "(\w+)"', blk)
        if i:
            zones[i.group(1)] = (re.search(r'sandTypeId = "(\w+)"', blk).group(1),
                                 re.search(r'requires = "(\w+)"', blk).group(1))
    eco = luau("src/shared/Data/Economy.luau")
    packs = [(int(g), int(r)) for g, r in
             re.findall(r"gems = (\d+), robux = (\d+)", luau("src/shared/Data/GemPacks.luau"))]
    prod = luau("src/shared/Data/Products.luau")
    sp = re.search(r'id = "season_pass".*?priceRobux = (\d+)', prod, re.S)
    cb = re.search(r'id = "coin_boost".*?priceRobux = (\d+)', prod, re.S)
    return dict(
        sand=sand, zones=zones, packs=packs,
        pass_robux=int(sp.group(1)), boost_robux=int(cb.group(1)),
        boost_s=eval(re.search(r"coinBoost = \{\s*durationSeconds = ([\d *]+),", eco).group(1)),
        max_gems=ds.load_max_gems(),
        daily_gems=sum(int(a) for a in re.findall(r'kind = "gems", amount = (\d+)', eco)),
    )


def check_data(d):
    out = pp.check_data()
    model = {z: f for z, f in FIXED_FACTORS.items()}
    for zid, (sid, req) in d["zones"].items():
        f = d["sand"].get(sid)
        if zid not in model:
            out.append(f"  Event-Zone in den Daten: {zid} (Sandsorte {sid}, Faktor {f:g} = Platzhalter, requires {req})")
            continue
        if f != model.get(zid):
            out.append(f"  ABWEICHUNG Zone {zid}: Daten {f}, Modell {model.get(zid)}")
    out.append(f"  Zones/SandTypes: {', '.join(f'{z} x{d['sand'][s]:g} ({r})' for z, (s, r) in d['zones'].items())}")
    out.append(f"  Saison-Pass {d['pass_robux']} Robux, Münz-Boost {d['boost_robux']} Robux / {d['boost_s'] // 60} min,"
               f" maxGems {d['max_gems']:,}")
    out.append(f"  Gem-Pakete: {', '.join(f'{g} Gems / {r} R' for g, r in d['packs'])}")
    return out


# ---------------------------------------------------------------------------
# 1. Event-Zone im Modell aus 2.7 (Zone mit dem höchsten Faktor, Event-Zone ohne Funde)
# ---------------------------------------------------------------------------

class EventPlayer(ss.StormPlayer):
    factor = None  # None = keine Saison

    @property
    def zone(self):
        best = super().zone
        if self.factor is not None and EVENT_NODE in self.owned and self.factor > best[1]:
            return ("event", self.factor, EVENT_NODE, 0.0)
        return best

    def _gather_finds(self, zone, t_start, dur):
        if zone == "event":
            self.cum_gather += dur
            self.gather_by_zone["event"] = self.gather_by_zone.get("event", 0.0) + dur
            return 0.0
        return super()._gather_finds(zone, t_start, dur)


def campaign_with(factor, runs=10, **kw):
    EventPlayer.factor = factor
    orig = ss.StormPlayer
    ss.StormPlayer = EventPlayer
    try:
        return ss.campaign(ss.s_tree_end, runs=runs, **kw)
    finally:
        ss.StormPlayer = orig
        EventPlayer.factor = None


MS = [("collect_rate_1", "Upgrade 1"), ("collect_tool_2", "Schaufel"), ("collect_tool_3", "Eimerkette"),
      ("collect_tool_4", "Mini-Bagger"), ("collect_tool_5", "Saugroboter"), ("collect_tool_6", "Großmaschine"),
      ("END", "Baumende")]


def run1_line(res):
    t = res[0]["times"]
    end = max(tt for tt, i, _, _ in res[0]["log"])
    vals = [t.get(k) if k != "END" else end for k, _ in MS]
    return vals


def section_factor():
    ss.section("1. Preisfaktor Event-Sand (Zone ab collect_tool_2, keine Funde, Spieler gräbt in der besten Zone)")
    variants = [("ohne Saison", None, {})] + [(f"x{f}", f, {}) for f in FACTORS]
    base = None
    print(f"  {'Variante':<12}" + "".join(f"{lbl:>13}" for _, lbl in MS) + f"{'10 Läufe':>11}{'Kristalle':>10}{'L10':>7}")
    rows = {}
    for name, f, kw in variants:
        res = campaign_with(f, **kw)
        r1 = run1_line(res)
        tot = sum(x["t"] for x in res)
        rows[name] = (r1, tot, res[-1]["total_c"], res[-1]["t"])
        if base is None:
            base = rows[name]
        cells = []
        for v, b in zip(r1, base[0]):
            cells.append(f"{ss.fmt_t(v)} ({(v / b - 1) * 100:+.0f}%)" if f is not None else ss.fmt_t(v))
        print(f"  {name:<12}" + "".join(f"{c:>13}" for c in cells)
              + f"{ss.fmt_t(tot):>11}{res[-1]['total_c']:>10}{ss.fmt_t(res[-1]['t']):>7}")
    print("\n  Gegenprobe Gamepässe (Lauf 1, gleiche Spalten):")
    for name, f, kw in [("2x ohne Saison", None, dict(coin_mult=2.0)), (f"2x + x{EVENT_FACTOR}", EVENT_FACTOR, dict(coin_mult=2.0)),
                        ("AutoDig ohne", None, dict(autodig=True)), (f"AutoDig + x{EVENT_FACTOR}", EVENT_FACTOR, dict(autodig=True))]:
        res = campaign_with(f, **kw)
        r1 = run1_line(res)
        tot = sum(x["t"] for x in res)
        print(f"  {name:<16}" + "".join(f"{ss.fmt_t(v):>9}" for v in r1) + f"   10 Läufe {ss.fmt_t(tot)}, Kristalle {res[-1]['total_c']}")

    # Ertrag in der Event-Zone gegenüber der besten festen Zone (Sandverkauf; Verkauf-Ast und Kristalle
    # wirken auf beide gleich, 2x Münzen und Boost auch: das Verhältnis ist nur F / Zonenfaktor).
    print("\n  Ertrag Event-Zone / beste feste Zone (nur Sand, ohne Funde der festen Zone):")
    print(f"  {'Faktor':<8}" + "".join(f"{ZONE_DE[z]:>13}" for z in FIXED_FACTORS))
    for f in FACTORS:
        print(f"  x{f:<7}" + "".join(f"{f / zf * 100:>12.0f}%" for zf in FIXED_FACTORS.values()))
    return rows


# ---------------------------------------------------------------------------
# 2. Punkte: secondsPerPoint, Grabanteil je Gang
# ---------------------------------------------------------------------------

WALK = st.WALK_ONE_WAY_S


def dig_share(g, big=False, autodig=False):
    """Anteil echter Grabzeit (Sand fließt) an der Zeit in der Zone; g = Tank / Rate in s."""
    if big:
        g = 2 * g
    if autodig:
        # sammelt schon auf dem Rückweg (5 s), Gang = Feldzeit + 2 Wege
        field = max(g - WALK, 0.0)
        return g / (field + 2 * WALK)
    return g / (g + 2 * WALK)


def run1_dig_by_tool():
    """Lauf 1 (Modell 2.7, ohne Saison): Grabzeit und Gangzeit je Werkzeug."""
    p = ss.StormPlayer(random.Random(SEED), ss.new_state(), ss.tree())
    while p.t < ss.MAX_RUN_S and not p.done():
        p.run()
    by = {}
    for _, tool, _, gather, run_len, _ in p.runs:
        a = by.setdefault(tool, [0.0, 0.0])
        a[0] += gather
        a[1] += run_len
    return by


def section_points():
    ss.section(f"2. Saison-Punkte: secondsPerPoint = {SECONDS_PER_POINT}")
    print("  Grabanteil (Sand fließt) an der Zeit in der Zone, Weg 5 s je Richtung:")
    print(f"  {'g = Tank/Rate':<14}{'normal':>9}{'Gr. Tank':>10}{'Auto-Dig':>10}{'beide':>8}{'Punkte/Gang':>13}")
    for g in [3, 5, 10, 15, 20, 30, 60]:
        print(f"  {g:>6} s       {dig_share(g) * 100:>8.0f}%{dig_share(g, big=True) * 100:>9.0f}%"
              f"{dig_share(g, autodig=True) * 100:>9.0f}%{dig_share(g, True, True) * 100:>7.0f}%{g / SECONDS_PER_POINT:>13.1f}")
    by = run1_dig_by_tool()
    print("\n  Lauf 1 (ohne Saison): Grabzeit / Gangzeit je Werkzeug")
    tot_g = tot_r = 0.0
    for tool in ["hand", "shovel", "bucket_chain", "mini_digger", "vacuum_robot", "mega_machine"]:
        if tool in by:
            g, r = by[tool]
            tot_g += g
            tot_r += r
            print(f"    {st.TOOL_NAME[tool]:<14} {g / r * 100:5.0f}%  ({ss.fmt_t(g)} Graben in {ss.fmt_t(r)})")
    print(f"    {'gesamt':<14} {tot_g / tot_r * 100:5.0f}%")
    print("\n  Variante: Ziele gelten für Zeit in der Zone statt Grabzeit (Grabanteil a):")
    for a in [0.46, 0.6, 0.67, 0.8]:
        need_cas = CASUAL_MIN * 60 * a * SEASON_DAYS / THRESHOLDS[12]
        need_heavy = HEAVY_MIN * 60 * a * 21 / THRESHOLDS[-1]
        print(f"    a = {a * 100:3.0f} %: Gelegenheit erreicht Stufe {tier_of(CASUAL_MIN * 60 * a * SEASON_DAYS / SECONDS_PER_POINT)},"
              f" Vielspieler Stufe 20 an Tag {THRESHOLDS[-1] * SECONDS_PER_POINT / (HEAVY_MIN * 60 * a):4.1f};"
              f" Ziele träfe secondsPerPoint <= {min(need_cas, need_heavy):4.1f}")
    print("\n  Punkte je Tag (echtes Graben):")
    for mins in [10, 15, 20, 30, 45, 60, 75, 90, 120]:
        print(f"    {mins:>4} min -> {mins * 60 / SECONDS_PER_POINT:6.0f} Punkte/Tag, Spur (Stufe 20 = {THRESHOLDS[-1]:,})"
              f" nach {THRESHOLDS[-1] * SECONDS_PER_POINT / 60 / mins:5.1f} Tagen")


# ---------------------------------------------------------------------------
# 3./4. Pass: Stufen, Ziele, Monte Carlo
# ---------------------------------------------------------------------------

def tier_of(points):
    return sum(1 for t in THRESHOLDS if points >= t)


def day_of_tier(n, minutes):
    return THRESHOLDS[n - 1] * SECONDS_PER_POINT / 60 / minutes


def mc(mean_min, p_play, sigma, start_day=1, trials=20000, seed=SEED):
    """Monte Carlo: an jedem Tag spielt der Spieler mit p_play, Minuten lognormal mit Mittel mean_min."""
    rng = random.Random(seed)
    mu = math.log(mean_min) - sigma ** 2 / 2
    tiers, full_day = [], []
    for _ in range(trials):
        pts = 0.0
        done = None
        for day in range(start_day, SEASON_DAYS + 1):
            if rng.random() < p_play:
                mins = rng.lognormvariate(mu, sigma) if sigma > 0 else mean_min
                pts += mins * 60 / SECONDS_PER_POINT
            if done is None and pts >= THRESHOLDS[-1]:
                done = day
        tiers.append(tier_of(min(pts, THRESHOLDS[-1])))
        full_day.append(done)
    tiers.sort()
    return tiers, full_day


def pct(xs, q):
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def section_pass(d):
    ss.section("3./4. Saison-Pass: 20 Stufen, Ziele")
    assert len(THRESHOLDS) == 20 == len(FREE) == len(PREMIUM)
    assert all(a < b for a, b in zip(THRESHOLDS, THRESHOLDS[1:])), "Stufen aufsteigend"
    assert all(a <= b for a, b in zip(INCREMENTS, INCREMENTS[1:])), "Zuwachs nie kleiner"
    print(f"  {'St.':>3}{'Punkte':>8}{'+':>6}{'Graben':>9}{'Gel. Tag':>10}{'Viel Tag':>10}   {'Gratis':<22}{'Premium':<34}")
    for i in range(20):
        n = i + 1

        def fmt(r):
            k, v = r
            if k == "gems":
                return f"{v} Gems"
            if k == "coinBoost":
                return f"2x Münzen {v // 60} min"
            if k == "luck":
                return f"Glück x2 {v // 60} min"
            it = PASS_ITEMS[v]
            return f"{v} ({ds.DE[it[2]]}, {it[3]})"
        print(f"  {n:>3}{THRESHOLDS[i]:>8,}{INCREMENTS[i]:>6}{ss.fmt_t(THRESHOLDS[i] * SECONDS_PER_POINT):>9}"
              f"{day_of_tier(n, CASUAL_MIN):>10.1f}{day_of_tier(n, HEAVY_MIN):>10.1f}   {fmt(FREE[i]):<22}{fmt(PREMIUM[i]):<34}")

    cas_pts = CASUAL_MIN * 60 * SEASON_DAYS / SECONDS_PER_POINT
    cas_tier = tier_of(cas_pts)
    heavy_day = day_of_tier(20, HEAVY_MIN)
    print(f"\n  Gelegenheitsspieler {CASUAL_MIN} min x {SEASON_DAYS} Tage = {cas_pts:,.0f} Punkte -> Stufe {cas_tier}"
          f" ({cas_tier / 20 * 100:.0f} %), Stufe {cas_tier} an Tag {day_of_tier(cas_tier, CASUAL_MIN):.1f},"
          f" Stufe {cas_tier + 1} bräuchte Tag {day_of_tier(cas_tier + 1, CASUAL_MIN):.1f}")
    print(f"  Vielspieler {HEAVY_MIN} min/Tag: Stufe 20 an Tag {heavy_day:.1f} (Ende Woche 3 = Tag 21,"
          f" Puffer {21 - heavy_day:.1f} Tage); Ende Woche 1/2: Stufe {tier_of(7 * HEAVY_MIN * 6)}/{tier_of(14 * HEAVY_MIN * 6)}")
    assert 13 <= cas_tier <= 14, "Gelegenheitsspieler etwa zwei Drittel"
    assert heavy_day <= 21, "Vielspieler vor Ende Woche 3"
    print(f"  Ganze Spur in 28 Tagen ab {THRESHOLDS[-1] * SECONDS_PER_POINT / 60 / SEASON_DAYS:.0f} min Graben je Tag")
    print(f"  Obergrenze Punkte (Summe aller Stufen, Testfall 5.5a) = {THRESHOLDS[-1]:,}")

    print("\n  Monte Carlo (20.000 Spieler je Zeile, feste Seeds): Stufe am Saisonende (10 % / Median / 90 %),"
          " Anteil >= 13, Tag Stufe 20 (Median)")
    cases = [
        ("Gelegenheit 30 min, jeden Tag", 30, 1.0, 0.0, 1),
        ("Gelegenheit 30 min, 85 % der Tage, Streuung", 30, 0.85, 0.5, 1),
        ("Gelegenheit 30 min, Einstieg Tag 8", 30, 1.0, 0.0, 8),
        ("Gelegenheit 30 min, Einstieg Tag 15", 30, 1.0, 0.0, 15),
        ("Kurzspieler 15 min (Annahme 2.6/2.7)", 15, 0.85, 0.5, 1),
        ("30 min in der Zone (~67 % Graben = 20 min)", 20, 0.85, 0.5, 1),
        ("Mittel 60 min, 85 %, Streuung", 60, 0.85, 0.5, 1),
        ("Vielspieler 120 min, jeden Tag", 120, 1.0, 0.0, 1),
        ("Vielspieler 120 min, 85 %, Streuung", 120, 0.85, 0.5, 1),
        ("Vielspieler 120 min in der Zone (~67 % = 80 min)", 80, 0.85, 0.5, 1),
    ]
    for k, (name, mins, p, sg, start) in enumerate(cases):
        tiers, full = mc(mins, p, sg, start, seed=SEED + k)
        fin = sorted(x for x in full if x is not None)
        share13 = sum(1 for t in tiers if t >= 13) / len(tiers)
        w3 = sum(1 for x in full if x is not None and x <= 21) / len(full)
        med = fin[len(fin) // 2] if len(fin) * 2 > len(full) else None
        print(f"    {name:<48} {pct(tiers, .1):>2} / {pct(tiers, .5):>2} / {pct(tiers, .9):>2}"
              f"   >=13: {share13 * 100:5.1f} %   Stufe 20 bis Tag 21: {w3 * 100:5.1f} %   Median Tag 20: {med if med else '-'}")


def knapsack_gems(budget, packs):
    best = [0] * (budget + 1)
    for b in range(budget + 1):
        for g, r in packs:
            if r <= b:
                best[b] = max(best[b], best[b - r] + g)
    return best[budget]


def section_value(d):
    ss.section("3./4./5. Wert der Spuren, Ersatz-Gems, Abholfrist")
    packs = d["packs"]
    R = d["pass_robux"]
    refs = {
        f"beste Kombination für <= {R} R (Knapsack)": knapsack_gems(R, packs),
        "Kurs 100er-Paket (49 R)": R * packs[0][0] / packs[0][1],
        "Kurs 1.200er-Paket (499 R)": R * 1200 / 499,
        "bester Kurs (7.000er-Paket)": R * max(g / r for g, r in packs),
    }

    def tot(track, upto=20, kind="gems"):
        return sum(v for k, v in track[:upto] if k == kind)
    cas = tier_of(CASUAL_MIN * 60 * SEASON_DAYS / SECONDS_PER_POINT)
    pg = tot(PREMIUM)
    print(f"  Premium-Gems gesamt {pg}, bis Stufe {cas} (Gelegenheit) {tot(PREMIUM, cas)}")
    for name, v in refs.items():
        print(f"    gegen {name:<44} {v:7.0f} Gems -> Anteil {pg / v * 100:5.1f} %")
    assert pg / min(refs.values()) <= PREMIUM_GEMS_MAX_SHARE, "Premium-Gems höchstens 50 %"
    lim = PREMIUM_GEMS_MAX_SHARE * R * packs[0][0] / packs[0][1]
    print(f"  DataCheck-Regel (einfach, nur Daten): Premium-Gems <= {PREMIUM_GEMS_MAX_SHARE * 100:.0f} % x {R} R x"
          f" {packs[0][0]}/{packs[0][1]} Gems je R (kleinstes Paket) = {lim:.1f} -> {pg} ok: {pg <= lim}")
    assert all(isinstance(v, int) and 0 < v <= d["max_gems"] for t in (FREE, PREMIUM) for k, v in t if k == "gems")
    print(f"  Gratis-Gems gesamt {tot(FREE)}, bis Stufe {cas} {tot(FREE, cas)} (Daily: 35 Gems/Woche = 140 je Saison + 4 Eisenkisten)")
    for lbl, track in (("Gratis", FREE), ("Premium", PREMIUM)):
        cb, lk = tot(track, kind="coinBoost"), tot(track, kind="luck")
        cbc, lkc = tot(track, cas, "coinBoost"), tot(track, cas, "luck")
        print(f"  {lbl:<8} 2x Münzen {cb // 60} min (bis St. {cas}: {cbc // 60}), Glück {lk // 60} min (bis St. {cas}: {lkc // 60}),"
              f" 2x-Münzen-Zeit zum Produktpreis = {cb / d['boost_s'] * d['boost_robux']:.0f} R")
    boost_r = tot(PREMIUM, kind="coinBoost") / d["boost_s"] * d["boost_robux"]
    gem_r = pg * packs[0][1] / packs[0][0]
    print(f"  Premium zum Listenpreis: Gems {gem_r:.0f} R (Kurs 100er) + 2x-Münzen {boost_r:.0f} R"
          f" = {gem_r + boost_r:.0f} R plus 3 feste Items und Glück, Preis {R} R")
    print(f"  Premium-Gems = {pg // 400} Event-Kiste(n) zu 400 Gems; mit Gratis-Gems {pg + tot(FREE)}")

    items = ds.load_items()
    ids = {it["id"] for it in items}
    for iid, (kind, name, rar, eff) in PASS_ITEMS.items():
        assert iid not in ids, f"{iid} existiert schon"
        assert iid.startswith(kind + "_" + rar + "_")
        same = sorted({it["effectBp"] for it in items if it["rarity"] == rar and "event" in it["crates"]})
        print(f"  Pass-Item {iid:<26} {kind:<12} {ds.DE[rar]:<10} effectBp {eff} (Event-Pool {ds.DE[rar]}: {same}), ID frei")
        assert [eff] == same

    # 5. Ersatz-Gems
    print(f"\n  Ersatz-Gems bei Doppelkauf: Vorschlag {DUPLICATE_GEMS}")
    combo = knapsack_gems(R, packs)
    print(f"    {R} R in Gem-Paketen: höchstens {combo} Gems (550 + 3 x 100 für 396 R); Kurs 1.200er {R * 1200 / 499:.0f}")
    assert DUPLICATE_GEMS == combo
    print(f"    {DUPLICATE_GEMS} Gems / {R} R = {DUPLICATE_GEMS / R:.2f} Gems je Robux, schlechter als jedes Paket ab 499 R"
          f" ({1200 / 499:.2f} / {3200 / 1199:.2f} / {7000 / 2499:.2f}): ein absichtlicher Doppelkauf lohnt nie")
    print(f"  Abholfrist: {CLAIM_DAYS} Tage nach Saisonende")


# ---------------------------------------------------------------------------
# 6. Event-Kiste und Pool
# ---------------------------------------------------------------------------

def roll_with_pity(rng, odds, pity, cnt):
    """Regeln wie Logic/CrateRoll (siehe directshop_4_6.pity_rates)."""
    e, l = cnt
    if l >= pity[1] - 1:
        min_rank = ds.RANK["legendary"]
    elif e >= pity[0] - 1:
        min_rank = ds.RANK["epic"]
    else:
        min_rank = 1
    allowed = [r for r in ds.RARITIES if ds.RANK[r] >= min_rank and odds[r] > 0]
    x = rng.random() * sum(odds[r] for r in allowed)
    for r in allowed:
        x -= odds[r]
        if x < 0:
            break
    if ds.RANK[r] >= ds.RANK["legendary"]:
        cnt[:] = [0, 0]
    elif r == "epic":
        cnt[:] = [0, l + 1]
    else:
        cnt[:] = [e + 1, l + 1]
    return r


def section_crate(d):
    ss.section("6. Event-Kiste: Quoten, Pool, Kosten")
    src = luau("src/shared/Data/Crates.luau")
    crates = ds.load_crates()
    ev, gold = crates["event"], crates["gold"]
    same_ref = re.search(r'id = "event".*?odds = Odds\.(\w+)', src, re.S).group(1) == "gold"
    print(f"  event: {ev['currency']} {ev['price']}, Quoten = Odds.gold (gleiche Referenz): {same_ref},"
          f" Pity {ev['pity']} = Gold {gold['pity']}: {ev['pity'] == gold['pity']}, eventOnly {ev['eventOnly']}")
    assert same_ref and ev["odds"] == gold["odds"] and ev["pity"] == gold["pity"] and ev["price"] == 400

    items = ds.load_items()
    pool = {r: [it for it in items if "event" in it["crates"]] for r in ds.RARITIES}
    gaps = []
    print(f"  {'Seltenheit':<13}{'Quote':>7}{'Event':>6}{'Gold':>6}  Arten im Event-Pool, effectBp (Gold)")
    for r in ds.RARITIES:
        evr = [it for it in pool[r] if it["rarity"] == r]
        gor = [it for it in items if it["rarity"] == r and "gold" in it["crates"]]
        kinds = sorted(it["id"].split("_")[0] for it in evr)
        effs = sorted({it["effectBp"] for it in evr})
        geffs = sorted({it["effectBp"] for it in gor})
        print(f"  {ds.DE[r]:<13}{ev['odds'][r] / 100:>6.1f}%{len(evr):>6}{len(gor):>6}  {kinds} {effs} ({geffs})")
        if ev["odds"][r] > 0 and len(evr) < 3:
            gaps.append(f"{r}: nur {len(evr)} Items (DataCheck verlangt 3)")
        if ev["odds"][r] > 0 and set(kinds) != {"skin", "companion", "toolVariant"}:
            gaps.append(f"{r}: nicht alle drei Arten")
        if evr and effs != geffs:
            gaps.append(f"{r}: effectBp {effs} weicht von Gold {geffs} ab")
        if ev["odds"][r] == 0 and evr:
            gaps.append(f"{r}: Items ohne Quote (fallen nie)")
    mixed = [it["id"] for it in items if "event" in it["crates"] and len(it["crates"]) > 1]
    if mixed:
        gaps.append(f"Event-Items auch in anderen Kisten: {mixed}")
    names = [it["name"] for it in items if "event" in it["crates"]]
    if any("Sandwurm" in n for n in names):
        gaps.append("Name 'Saison-Sandwurm': Konzept übernimmt den Sandwurm aus dem Teaser ausdrücklich nicht (Text, keine Zahl)")
    print("  Lücken: " + ("keine in Zahlen; Hinweise: " if all("Name" in g for g in gaps) else "") + ("; ".join(gaps) or "keine"))

    rates = ds.pity_rates(ev["odds"], *ev["pity"])
    lp = rates["legendary"] + rates["mythic"]
    opens = 1 / lp
    print(f"  Langzeitrate Legendär+ {float(lp) * 100:.3f} %, mittlere Öffnungen bis Legendär+ (ab Zähler 0, exakt) {float(opens):.2f}")
    print(f"    = {float(opens) * ev['price']:,.0f} Gems einzeln, {float(opens) * ev['price'] * 10 / 11:,.0f} Gems im 10er-Paket")
    for r in ["uncommon", "rare", "epic", "legendary", "mythic"]:
        n = len([it for it in pool[r] if it["rarity"] == r])
        p_item = rates[r] / n
        pg = [it for it in items if it["rarity"] == r and "gold" in it["crates"]]
        print(f"    bestimmtes {ds.DE[r]:<13} Item: {float(p_item) * 100:6.3f} % je Öffnung, EV {float(ev['price'] / p_item):>10,.0f} Gems"
              f" (Gold-Pool: {float(rates[r] / len(pg)) * 100:6.3f} %)")

    rng = random.Random(SEED)
    trials = 4000
    res = {"any_leg": [], "spec_leg": [], "all_leg": [], "any_myth": [], "all15": []}
    ev_items = {r: [it["id"] for it in pool[r] if it["rarity"] == r] for r in ds.RARITIES}
    target_leg = ev_items["legendary"][0]
    for _ in range(trials):
        cnt = [0, 0]
        have = set()
        k = 0
        marks = {}
        while len(marks) < 5 and k < 20000:
            k += 1
            r = roll_with_pity(rng, ev["odds"], ev["pity"], cnt)
            it = rng.choice(ev_items[r])
            have.add(it)
            if ds.RANK[r] >= 5:
                marks.setdefault("any_leg", k)
            if r == "mythic":
                marks.setdefault("any_myth", k)
            if it == target_leg:
                marks.setdefault("spec_leg", k)
            if all(x in have for x in ev_items["legendary"]):
                marks.setdefault("all_leg", k)
            if len(have) == 15:
                marks.setdefault("all15", k)
        for key in res:
            res[key].append(marks.get(key, k))
    print(f"  Monte Carlo ({trials} Spieler, Event-Pity ab 0): Öffnungen Mittel / Median / 90 % -> Gems einzeln (Mittel)")
    lbl = {"any_leg": "erstes Legendär+", "spec_leg": "bestimmtes Legendär", "all_leg": "alle 3 Legendär",
           "any_myth": "erstes Mythisch", "all15": "ganzer Pool (15)"}
    for key, xs in res.items():
        xs.sort()
        mean = sum(xs) / len(xs)
        print(f"    {lbl[key]:<22} {mean:7.1f} / {pct(xs, .5):>5} / {pct(xs, .9):>5} -> {mean * ev['price']:>9,.0f} Gems"
              f" ({mean * ev['price'] * 10 / 11 / knapsack_rate(d):>7,.0f} R zum besten Kurs, 10er-Paket)")
    print(f"  Premium-Gems ({sum(v for k, v in PREMIUM if k == 'gems')}) = 1 Event-Kiste: Legendär+ mit"
          f" {float(rates['legendary'] + rates['mythic']) * 100:.1f} % (Langzeit), Episch+ mit"
          f" {float(rates['epic'] + rates['legendary'] + rates['mythic']) * 100:.1f} %")


def knapsack_rate(d):
    return max(g / r for g, r in d["packs"])


# ---------------------------------------------------------------------------

def main():
    d = load_data()
    ss.section("0. Datenabgleich")
    for line in check_data(d):
        print(line)
    section_factor()
    section_points()
    section_pass(d)
    section_value(d)
    section_crate(d)
    ss.section("Vorschlag (zum Übertragen)")
    print(f"  SandTypes \"season\".priceFactor = {EVENT_FACTOR}; Zone season_camp requires = \"{EVENT_NODE}\"")
    print(f"  Economy.seasonPass = {{ secondsPerPoint = {SECONDS_PER_POINT}, duplicateGems = {DUPLICATE_GEMS},"
          f" claimGraceDays = {CLAIM_DAYS}, premiumGemsMaxPercent = {int(PREMIUM_GEMS_MAX_SHARE * 100)} }}")
    print(f"  Stufen (Punkte): {THRESHOLDS}")


if __name__ == "__main__":
    main()
