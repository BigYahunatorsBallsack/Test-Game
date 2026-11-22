"""Build the four machine beds, marker sounds and the timed listening preview."""

import json
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent
RATE = 48_000


def timeline(duration):
    return np.arange(round(duration * RATE)) / RATE


def phase(t, hz):
    duration = len(t) / RATE
    return 2 * np.pi * round(hz * duration) * t / duration


def tone(t, hz, angle=0):
    return np.sin(phase(t, hz) + angle)


def passband(t, rng, low, high):
    hz = np.fft.rfftfreq(len(t), 1 / RATE)
    response = (hz / (hz + low)) ** 2.7 / (1 + (hz / high) ** 4)
    filtered = np.fft.irfft(np.fft.rfft(rng.standard_normal(len(t))) * response, n=len(t))
    return filtered / np.sqrt(np.mean(filtered**2))


def rise(t, attack):
    return np.sin(np.pi / 2 * np.clip(t / attack, 0, 1)) ** 2


def decay(t, attack, tail):
    return rise(t, attack) * np.exp(-t / tail)


def around(t, duration, center, width):
    distance = (t - center + duration * .5) % duration - duration * .5
    return np.exp(-(distance / width) ** 2)


def add(mix, offset, layer, gain=1):
    start = round(offset * RATE)
    count = max(0, min(len(mix) - start, len(layer)))
    mix[start:start + count] += gain * layer[:count]


def conveyor(t, ctx, rng):
    motor = (.43*tone(t, 72) + .26*tone(t, 145, .79) + .11*tone(t, 291, 1.05))
    motor *= .91 + .09*tone(t, 3.04, .44)
    chain = .18*passband(t, rng, 364, 2370)
    chain *= .24 + .76*(.5+.5*tone(t, 18.25, .63))**4
    clacks = sum(around(t, ctx["durationSeconds"], at - .041, .020)
        for at in ctx["cues"]["Discharge"]["markerTimesSeconds"])
    return motor + chain + clacks * (.19*tone(t, 562) + .11*tone(t, 1094, .95))


def excavator(t, ctx, rng):
    period = ctx["durationSeconds"]
    lift = around(t, period, 1.37, .43)
    tip = around(t, period, 2.18, .25)
    wobble = .078*tone(t, 2.1) + .20*tone(t, .67, .45)
    engine = .46*np.sin(phase(t, 47)+wobble) + .26*tone(t, 94) + .10*tone(t, 188, .4)
    engine *= .79 + .21*(.5+.5*tone(t, 11.8, .45))**2
    pump = .115*passband(t, rng, 381, 2520) + .10*tone(t, 214, .91) + .066*tone(t, 428, .74)
    exhaust = .135*passband(t, rng, 100, 674)
    return engine + (lift*.95 + tip*.72+.12)*pump + exhaust


def vacuum(t, ctx, rng):
    cues = ctx["cues"]
    start = cues["IntakeEngage"]["markerTimesSeconds"][0]
    stop = cues["IntakeRelease"]["markerTimesSeconds"][0]
    gate = rise(t - start, .12) * rise(stop + .14 - t, .14)
    speed = .22*tone(t, 5.43, .32) + .075*tone(t, 12.1, .33)
    motor = .34*np.sin(phase(t, 168)+speed) + .17*tone(t, 336, .91) + .060*tone(t, 512, 1.4)
    air = .22*passband(t, rng, 431, 3160) + .10*passband(t, rng, 185, 1310)
    return (.59+.41*gate)*motor + (.23+.77*gate)*air


def harvester(t, ctx, rng):
    period = ctx["durationSeconds"]
    load = sum(around(t, period, at+.037,.145) for at in ctx["cues"]["CutterLoad"]["markerTimesSeconds"])
    beat = .69 + .31*(.5+.5*tone(t, 8.26, 1.1))**3
    diesel = .47*tone(t, 36.5) + .34*tone(t, 73, .59) + .18*tone(t, 146, .41)
    diesel *= beat*(.91+.09*load)
    drag = .20*passband(t,rng,115,886)*(.65+.35*load)
    rollers = (.066*tone(t, 226, .89) + .09*passband(t,rng,378,2070))*(.35+.65*load)
    return diesel + drag + rollers


def ring(t, hz, bend, tail):
    return np.sin(2*np.pi*(hz*t + .5*bend*t**2))*decay(t,.0031,tail)


def burst(marker, rng):
    duration, lows, highs, structure, peak = CUES[marker]
    t = timeline(duration)
    sound = np.zeros_like(t)
    for offset, count, gain in structure:
        layer_t = timeline(count)
        layer = passband(layer_t,rng,lows,highs)
        add(sound,offset,layer*decay(layer_t, min(.027,count*.19),count*.31),gain)
    for hz, bend, tail, gain in RESONANCES[marker]:
        sound += gain*ring(t,hz,bend,tail)
    return finish(sound,peak,.021)


CUES = {
    "Discharge": (.248, 609, 3580, ((0,.122,.28),(.045,.132,.23),(.088,.156,.19)), .21),
    "BucketCut": (.415, 287, 3140, ((0,.117,.41),(.027,.184,.20),(.115,.246,.26)), .35),
    "BucketLoaded": (.281, 342, 2310, ((0,.061,.18),(.047,.193,.16)), .25),
    "BucketDump": (.689, 472, 3390, ((0,.145,.24),(.072,.229,.35),(.174,.302,.29),(.292,.331,.236),(.495,.174,.115)), .37),
    "IntakeEngage": (.349, 594, 2780, ((.009,.332,.241),(.025,.087,.13)), .24),
    "IntakeSweep": (.212, 613, 2970, ((0,.174,.229),(.055,.139,.123)), .19),
    "IntakeRelease": (.275, 437, 2270, ((0,.239,.217),(.033,.138,.104)), .20),
    "CutterLoad": (.546, 161, 2430, ((0,.179,.30),(.047,.348,.284),(.209,.302,.193)), .38),
}
RESONANCES = {
    "Discharge": ((219,-182,.036,.25),(788,-672,.014,.121)),
    "BucketCut": ((138,-77,.077,.46),(377,-541,.038,.163),(919,-1222,.015,.064)),
    "BucketLoaded": ((135,-81,.071,.40),(335,-330,.042,.20),(831,-341,.015,.065)),
    "BucketDump": ((147,-111,.064,.42),(540,-943,.022,.142)),
    "IntakeEngage": ((182,390,.122,.32),(386,722,.102,.148)),
    "IntakeSweep": ((477,101,.054,.132),),
    "IntakeRelease": ((318,-641,.075,.249),(562,-1060,.052,.116)),
    "CutterLoad": ((83,-39,.154,.46),(167,-109,.123,.29),(315,-114,.076,.133)),
}
LOOPS = {
    "bucket_chain": (conveyor,.31), "mini_digger": (excavator,.37),
    "vacuum_robot": (vacuum,.29), "mega_machine": (harvester,.43),
}


def finish(signal, peak, fade=0):
    signal = np.tanh(1.12*signal)
    if fade:
        span = round(fade * RATE)
        signal[-span:] *= .5+.5*np.cos(np.linspace(0,np.pi,span))
        signal[:24] *= np.linspace(0,1,24)
    return signal * (peak / np.max(np.abs(signal)))


def wav(name, samples):
    assert np.isfinite(samples).all() and np.max(np.abs(samples)) < .92
    with wave.open(str(ROOT / name), "wb") as stream:
        stream.setparams((1, 2, RATE, len(samples), "NONE", "PCM"))
        stream.writeframes(np.rint(samples*32767).astype("<i2").tobytes())


def build():
    manifest = json.loads((ROOT / "cue_sheet.json").read_text(encoding="utf-8"))
    preview = [np.zeros(round(.10*RATE))]
    for index, (rig, ctx) in enumerate(manifest["machines"].items()):
        loop, peak = LOOPS[rig]
        t = timeline(ctx["durationSeconds"])
        rng = np.random.default_rng(3701+9967*index)
        chamber = loop(t,ctx,rng)
        bed = finish(chamber+.069*np.roll(chamber,round(.016*RATE)),peak)
        wav(ctx["loopFile"],bed)
        section = np.r_[bed,bed,np.zeros(round(.65*RATE))]
        section[:round(.083*RATE)] *= rise(timeline(.083),.083)
        end = 2*len(bed)
        fade_out = round(.15*RATE)
        section[end-fade_out:end] *= rise(timeline(.15),.15)[::-1]
        for marker,cue in ctx["cues"].items():
            effect = burst(marker,rng)
            wav(cue["file"],effect)
            for cycle in range(2):
                for at in cue["markerTimesSeconds"]:
                    add(section,ctx["durationSeconds"]*cycle+at,effect)
        preview.append(section)
        print(f"{rig}  WorkLoop {len(t)/RATE:.2f} s, {len(ctx['cues'])} cue files")
    wav("maschinen_hoervergleich.wav",np.concatenate(preview))


if __name__ == "__main__":
    build()
