"""Build first-minute sounds and place the previews on the exported clip markers."""

import json

import numpy as np

from build_discovery_audio import ROOT, RATE, add, band, edge_fade, fade_in, master, timebase, write_wave


OUT = ROOT / "starter"
SAND = {
    "HandSandTouch": (.244, (695, 3280), ((0,.144,.51),(.072,.124,.24)), (218, .24, .038), .29),
    "HandLoaded": (.205, (580, 2520), ((0,.113,.36),(.056,.110,.19)), (296, .32, .032), .25),
    "HandDeposit": (.318, (706, 3700), ((0,.183,.47),(.064,.142,.27),(.124,.164,.18)), (189, .28, .040), .31),
    "SpadeCut": (.361, (420, 4000), ((0,.117,.60),(.032,.216,.34),(.136,.194,.17)), (332, .43, .079), .39),
    "SpadeLoaded": (.279, (474, 2890), ((0,.161,.37),(.067,.190,.21)), (227, .35, .065), .29),
    "SpadeDump": (.596, (568, 3890), ((0,.203,.32),(.074,.236,.51),(.157,.285,.36),(.287,.202,.24)), (173, .35, .051), .40),
}


def grit(name, rng):
    duration, color, sprays, main, peak = SAND[name]
    samples = timebase(duration)
    mixed = np.zeros_like(samples)
    for at, seconds, gain in sprays:
        t = timebase(seconds)
        puff = band(t, rng, *color) * fade_in(t, .007) * np.exp(-t / (seconds * .36))
        add(mixed, at, puff, gain)
    hz, gain, release = main
    phase = 2*np.pi*(hz*samples - 108*samples**2)
    mixed += gain*np.sin(phase)*fade_in(samples, .0043)*np.exp(-samples/release)
    if name.startswith("Spade"):
        resonant = np.sin(2*np.pi*1.94*hz*samples + .43) * np.exp(-samples/(release*.67))
        mixed += .20*resonant*fade_in(samples,.0028)
    edge_fade(mixed,.003,.026)
    return master(mixed,peak)


def notification(name, rng):
    if name == "tankFull":
        duration, peak = .468, .40
        pattern = ((0, 392.00, .45), (.113, 523.25, .48))
    else:
        duration, peak = .887, .55
        pattern = ((.006, 523.25, .53), (.075, 659.26, .48), (.159, 783.99, .50), (.278, 1046.50, .39))
    entire = timebase(duration)
    mixed = np.zeros_like(entire)
    for i, (at, hz, gain) in enumerate(pattern):
        t = timebase(duration-at)
        decay = .084 + .020*i
        note = np.sin(2*np.pi*hz*t)*np.exp(-t/decay)
        note += .25*np.sin(2*np.pi*hz*2.045*t+.83)*np.exp(-t/(decay*.7))
        add(mixed, at, note*fade_in(t,.0078), gain)
        if name == "sold":
            ring = np.sin(2*np.pi*(hz*2.48*t - 316*t**2)) * np.exp(-t/.031)
            tick = band(t, rng, 964, 5150) * np.exp(-t/.017)
            add(mixed, at, (.56*ring+.15*tick)*fade_in(t,.0016), .20)
    if name == "sold":
        for at, hz in ((.04,234),(.100,267),(.239,337),(.328,383)):
            t = timebase(.104)
            tap = np.sin(2*np.pi*hz*t) + .22*band(t,rng, 722,3630)
            add(mixed, at, tap*fade_in(t,.003)*np.exp(-t/.024), .114)
    edge_fade(mixed,.003,.042)
    return master(mixed,peak)


def build():
    sheet = json.loads((OUT/"cue_sheet.json").read_text(encoding="utf-8"))
    keys = [(marker, cue["file"], clip["previewStartsAtSeconds"]+cue["markerSeconds"])
        for clip in sheet["clips"].values() for marker,cue in clip["cues"].items()]
    keys.extend((kind, cue["file"], cue["previewAtSeconds"]) for kind,cue in sheet["events"].items())
    preview = np.zeros(round(6.65*RATE))
    for index,(cue, name, at) in enumerate(keys):
        rng = np.random.default_rng(8731+1693*index)
        signal = grit(cue, rng) if cue in SAND else notification(cue,rng)
        write_wave(OUT/name, signal)
        add(preview,at,signal)
    write_wave(OUT/"start_hoerprobe.wav",preview)
    print(f"{len(keys)} cues, {len(preview)/RATE:.2f} seconds")


if __name__ == "__main__":
    build()
