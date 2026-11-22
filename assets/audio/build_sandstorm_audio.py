"""Build original audio for a single Prestige sandstorm transition."""

import json

import numpy as np

from build_discovery_audio import ROOT, RATE, add, band, edge_fade, fade_in, master, timebase, write_wave


OUT = ROOT / "sandstorm"


def transition(seconds, rng):
    t = timebase(seconds)
    gust = fade_in(t,.54) * fade_in(seconds-t,1.35)
    waves = .75+.16*np.sin(2*np.pi*(1.97*t-0.18*t*t))+.09*np.sin(2*np.pi*7.9*t+.42)
    body = .48*band(t,rng,104,1010) + .21*band(t,rng,43,275)
    friction = .22*band(t,rng,489,3580)*(0.65+0.35*np.sin(2*np.pi*2.7*t)**2)
    flow = gust*waves*(body+friction)
    wind_chord = np.sin(2*np.pi*(75*t+12*t*t))+.31*np.sin(2*np.pi*(155*t-9*t*t))
    flow += .14*wind_chord*gust**1.65
    for when,duration,amount in ((.22,.19,.09),(.37,.27,.11),(.56,.29,.12),(.82,.31,.095),(1.05,.31,.062),(1.32,.29,.033)):
        u=timebase(duration)
        drift=band(u,rng,588,3860)*fade_in(u,.018)*np.exp(-u/(duration*.30))
        add(flow,when,drift,amount)
    edge_fade(flow,.025,.089)
    return master(flow,.58)


def result(seconds, rng):
    t = timebase(seconds)
    brush = band(t,rng,732,3640)*fade_in(t,.016)*np.exp(-t/.063)
    answer=.13*brush
    answer += .22*np.sin(2*np.pi*147*t)*fade_in(t,.018)*np.exp(-t/.162)
    for when,hz,gain in ((.014,392.00,.48),(.141,523.25,.42),(.235,587.33,.40),(.386,783.99,.40),(.528,1046.50,.27)):
        u=timebase(seconds-when)
        key=np.sin(2*np.pi*hz*u)*np.exp(-u/.167)
        shimmer=.31*np.sin(2*np.pi*(2.024*hz*u+2.6*u*u)+.62)*np.exp(-u/.116)
        glass=.09*np.sin(2*np.pi*3.1*hz*u+1.20)*np.exp(-u/.049)
        phrase=(key+shimmer+glass)*fade_in(u,.010)
        add(answer,when,phrase,gain)
        add(answer,when+.097,phrase,gain*.16)
    edge_fade(answer,.009,.101)
    return master(answer,.55)


def build():
    sheet=json.loads((OUT/"cue_sheet.json").read_text(encoding="utf-8"))
    composers={"confirmed":transition, "revealed":result}
    mix=np.zeros(round(4.35*RATE))
    for index,cue in enumerate(sheet["cues"]):
        rng=np.random.default_rng(4118+7343*index)
        signal=composers[cue["phase"]](cue["durationSeconds"],rng)
        write_wave(OUT/cue["file"],signal)
        add(mix,cue["previewAtSeconds"],signal)
    write_wave(OUT/"sandsturm_hoerprobe.wav",mix)
    print("Two cues, 4.35 s preview")


if __name__ == "__main__":
    build()
