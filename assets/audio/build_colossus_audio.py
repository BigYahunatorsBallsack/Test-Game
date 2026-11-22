"""Build original audio cues for the Colossus event's art handoff."""

import json

import numpy as np

from build_discovery_audio import ROOT, RATE, add, band, edge_fade, fade_in, master, timebase, write_wave


OUT = ROOT / "colossus"


def resonance(t, hz, slope, attack, release):
    phase = 2*np.pi*(hz*t+.5*slope*t**2)
    return np.sin(phase)*fade_in(t,attack)*np.exp(-t/release)


def opened(rng):
    t = timebase(1.35)
    breeze = band(t, rng, 198, 1850)
    wind = .26*breeze*fade_in(t,.18)*np.exp(-t/.28)
    wind += .18*resonance(t, 154, -31, .038, .28)
    for at,hz,gain in ((.098, 293.66, .40),(.313, 391.99, .39)):
        tone_t=timebase(.82)
        tone=resonance(tone_t,hz,-16,.011,.142)+.24*resonance(tone_t,2.77*hz,0,.006,.052)
        add(wind,at,tone,gain)
    edge_fade(wind,.008,.075)
    return master(wind,.445)


def section(rng):
    t = timebase(1.43)
    ground = (
        .56*resonance(t,86,-30,.011,.183)
        + .31*resonance(t,160,-73,.014,.186)
        + .19*resonance(t,270,-188,.009,.071)
    )
    sand = band(t, rng, 365, 2890)*fade_in(t,.052)*np.exp(-t/.234)
    add(ground,.026,sand,.27)
    for at, duration, gain in ((.014,.18,.28),(.11,.24,.21),(.25,.31,.15),(.47,.32,.10),(.63,.31,.07)):
        u=timebase(duration)
        pieces=band(u,rng, 344,3620) + .36*resonance(u,223,-132,.0025,.041)
        add(ground,at,pieces*fade_in(u,.004)*np.exp(-u/(duration*.30)),gain)
    edge_fade(ground,.005,.080)
    return master(ground,.56)


def completed(rng):
    t = timebase(2.40)
    swell = .34*resonance(t,65.41,8,.078,.49)+.29*resonance(t,130.81,.9,.072,.46)
    swell += .15*band(t,rng,192,1760)*fade_in(t,.051)*np.exp(-t/.42)
    for at, hz, gain in ((.03,261.63,.40),(.18,329.63,.34),(.362,392.00,.38),
                        (.55,523.25,.40),(.797,783.99,.40),(.953,1046.50,.28)):
        u=timebase(2.40-at)
        note = resonance(u,hz,0,.010,.276) + .28*resonance(u,hz*2.013,3,.011,.132)
        note += .13*resonance(u,hz*3.077,-8,.006,.073)
        add(swell,at,note,gain)
        add(swell,at+.124,note,gain*.16)
    edge_fade(swell,.011,.146)
    return master(swell,.67)


def build():
    sheet=json.loads((OUT/"cue_sheet.json").read_text(encoding="utf-8"))
    voices={"opened":opened,"sectionRevealed":section,"completed":completed}
    preview=np.zeros(round(6.78*RATE))
    for index,cue in enumerate(sheet["cues"]):
        rng=np.random.default_rng(815+3089*index)
        audible=voices[cue["phase"]](rng)
        write_wave(OUT/cue["file"],audible)
        add(preview,cue["previewAtSeconds"],audible)
    write_wave(OUT/"koloss_hoerprobe.wav",preview)
    print("Three cues, 6.78 s preview")


if __name__ == "__main__":
    build()
