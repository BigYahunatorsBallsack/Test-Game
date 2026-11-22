"""Synthesize a continuous close-up loop for the oasis spring."""

import numpy as np

from build_discovery_audio import ROOT, band, edge_fade, master, place_cycle, roll_layer, timebase, write_wave


def build():
    seconds = 12.0
    t = timebase(seconds)
    rng = np.random.default_rng(540239)
    turbulence = .66 + .21 * roll_layer(t, 2.3, .7) + .13 * roll_layer(t, 3.8, 1.4)
    flow = (
        .18 * band(t, rng, 162, 775)
        + .61 * band(t, rng, 490, 2550) * turbulence
        + .11 * band(t, rng, 1560, 6200)
    )
    at = .14
    while at < seconds:
        duration = rng.uniform(.048, .11)
        splash_t = timebase(duration)
        pitch = rng.uniform(370, 760)
        phase = 2 * np.pi * (pitch * splash_t - 420 * splash_t**2)
        splash = .72 * band(splash_t, rng, 690, 4400) + .28 * np.sin(phase)
        splash *= np.exp(-splash_t / (duration * .23))
        edge_fade(splash, .007, .012)
        place_cycle(flow, at, splash, rng.uniform(.11, .33))
        at += rng.uniform(.086, .265)

    folder = ROOT / "oasis_spring"
    folder.mkdir(exist_ok=True)
    write_wave(folder / "quelle_plaetschern.wav", master(flow, .52))
    print("Oasis spring: 12 s mono WAV")


if __name__ == "__main__":
    build()
