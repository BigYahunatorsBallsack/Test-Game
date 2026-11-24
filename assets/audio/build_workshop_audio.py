"""Make original, short mono UI cues for the Every Last Grain workshop."""

from pathlib import Path

import numpy as np

from build_discovery_audio import RATE, add, band, edge_fade, fade_in, timebase, write_wave


OUTPUT = Path(__file__).resolve().parent / "workshop"


def strike(frequency, duration, decay, brightness=1.0):
    t = timebase(duration)
    partials = [(1.0, 0.68, 1.0), (2.02, 0.18, 0.57), (2.78, 0.11, 0.41), (4.22, 0.055, 0.24)]
    mix = np.zeros_like(t)
    for ratio, level, tail in partials:
        overtone = brightness if ratio > 1 else 1
        mix += overtone * level * np.sin(2 * np.pi * frequency * ratio * t) * np.exp(-t / (decay * tail))
    return mix * fade_in(t, 0.002)


def grain(rng, duration, lo, hi, decay):
    t = timebase(duration)
    return band(t, rng, lo, hi) * fade_in(t, 0.004) * np.exp(-t / decay)


def render():
    rng = np.random.default_rng(52031)

    select = np.zeros_like(timebase(0.105))
    add(select, 0.000, grain(rng, 0.080, 1750, 5500, 0.009), 0.085)
    add(select, 0.003, strike(585, 0.092, 0.021, 0.65), 0.31)

    learn = np.zeros_like(timebase(0.306))
    add(learn, 0.000, grain(rng, 0.12, 620, 3000, 0.040), 0.10)
    add(learn, 0.004, strike(360, 0.275, 0.055, 0.8), 0.43)
    add(learn, 0.049, strike(540, 0.255, 0.067, 0.8), 0.26)

    mastery = np.zeros_like(timebase(0.690))
    add(mastery, 0.000, grain(rng, 0.37, 750, 4400, 0.086), 0.14)
    add(mastery, 0.003, strike(218, 0.50, 0.085), 0.50)
    add(mastery, 0.074, strike(436, 0.54, 0.144, 0.85), 0.35)
    add(mastery, 0.198, strike(654, 0.47, 0.126, 0.7), 0.27)
    add(mastery, 0.273, strike(873, 0.41, 0.102, 0.62), 0.15)

    equip = np.zeros_like(timebase(0.279))
    add(equip, 0.000, grain(rng, 0.12, 920, 4100, 0.031), 0.09)
    add(equip, 0.004, strike(745, 0.125, 0.026, 0.7), 0.22)
    add(equip, 0.049, strike(680, 0.135, 0.029, 0.62), 0.17)
    add(equip, 0.102, strike(300, 0.17, 0.048, 0.43), 0.36)
    add(equip, 0.104, grain(rng, 0.145, 310, 2100, 0.035), 0.08)

    return {
        "Knoten": (select, 0.34),
        "Upgrade": (learn, 0.47),
        "Faehigkeit": (mastery, 0.57),
        "Variante": (equip, 0.43),
    }


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    audition = [np.zeros(round(0.12 * RATE))]
    for name, (sound, peak) in render().items():
        edge_fade(sound, 0.002, 0.025)
        sound *= peak / np.max(np.abs(sound))
        write_wave(OUTPUT / f"Werkstatt_{name}.wav", sound)
        audition.extend((sound, np.zeros(len(timebase(0.30)))))
    write_wave(OUTPUT / "Werkstatt_Hoervergleich.wav", np.concatenate(audition))


if __name__ == "__main__":
    build()
