"""Build the four original sandworm cues and a marker-synchronized WAV preview."""

import json
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent
RATE = 48_000


def timeline(duration):
    return np.arange(round(duration * RATE)) / RATE


def decay(t, attack, release):
    rise = np.sin(np.minimum(t / attack, 1) * np.pi / 2) ** 2
    return rise * np.exp(-t / release)


def sweep(t, frequency, slope, phase=0):
    return np.sin(2 * np.pi * (frequency * t + .5 * slope * t**2) + phase)


def band(t, rng, low, high):
    frequencies = np.fft.rfftfreq(len(t), 1 / RATE)
    response = (frequencies / (frequencies + low)) ** 2.6 / (1 + (frequencies / high) ** 4)
    noise = np.fft.irfft(np.fft.rfft(rng.standard_normal(len(t))) * response, n=len(t))
    return noise / np.sqrt(np.mean(noise**2))


def add(mix, at, sound, gain):
    start = round(at * RATE)
    count = max(0, min(len(mix) - start, len(sound)))
    mix[start:start + count] += gain * sound[:count]


def grit(mix, rng, texture, controls):
    for offset, duration, gain in controls:
        t = timeline(duration)
        layer = band(t, rng, *texture)
        add(mix, offset, layer * decay(t, .0027, duration * .26), gain)


def warning(rng):
    t = timeline(.65)
    swell = np.sin(np.pi * np.clip((t+.024)/.73, 0, 1)) ** 1.47
    flutter = .81 + .19 * sweep(t, 6.2, 8.6, .4)
    low = .39*sweep(t, 47, 24) + .33*sweep(t, 91, 17, .6) + .23*sweep(t, 168, 59, 1.1)
    gravel = .21*band(t, rng, 155, 1380) + .14*band(t, rng, 69, 560)
    sound = (low+gravel) * swell * flutter
    grit(sound, rng, (425, 3400), ((.052,.11,.04),(.21,.14,.064),(.36,.17,.094),(.509,.24,.122)))
    add(sound,.524,sweep(t,209,128) * decay(t,.067,.074),.092)
    # Leave room for the first instant of the breach impact.
    tail = np.clip((.65-t)/.123,0,1)
    return sound * np.sin(np.pi * tail/2)**2


def breach(rng):
    t = timeline(1.23)
    sound = (
        .62*sweep(t, 91, -36)*decay(t,.007,.104)
        + .43*sweep(t, 145, -63, .28)*decay(t,.012,.123)
        + .23*sweep(t, 239, -93)*decay(t,.020,.159)
    )
    sound += .43*band(t, rng, 145, 1640)*decay(t,.012,.201)
    sand = band(t, rng, 622, 3500)*decay(t,.062,.281)
    sand *= .78 + .22*sweep(t,7,-3.7,.7)
    add(sound,.024,sand,.245)
    add(sound,.116,(sweep(t,132,68)+.24*sweep(t,319,-60))*decay(t,.145,.179),.182)
    grit(sound, rng, (800,4900), ((.017,.10,.16),(.094,.13,.14),(.24,.17,.103),(.40,.22,.113),(.51,.23,.081),(.66,.21,.060),(.82,.18,.035)))
    return sound


def bite(rng):
    t = timeline(.455)
    sound = .68*sweep(t,117,-89)*decay(t,.0017,.037)
    sound += .32*sweep(t,289,-312)*decay(t,.0023,.029)
    sound += .20*sweep(t,683,-610)*decay(t,.0016,.014)
    grit(sound,rng,(650,4200), ((.002,.040,.32),(.027,.052,.23),(.081,.081,.083),(.132,.092,.047)))
    breath = band(t,rng,174,1660)*decay(t,.025,.078)
    add(sound,.032,breath,.151)
    return sound


def burrow(rng):
    t = timeline(.97)
    sound = .46*sweep(t,119,-67)*decay(t,.039,.152)
    sound += .23*sweep(t,214,-93,.35)*decay(t,.058,.177)
    sound += .285*band(t,rng,126,910)*decay(t,.054,.218)
    sweep_grit = band(t,rng,544,3250)*decay(t,.033,.252)
    add(sound,.062,sweep_grit*(.80+.20*sweep(t,10,-6.3)),.27)
    grit(sound,rng,(610,2800), ((.031,.16,.104),(.157,.19,.093),(.311,.20,.065),(.478,.25,.064),(.655,.22,.036)))
    add(sound,.386,sweep(t,77,-30)*decay(t,.017,.071),.15)
    return sound


def finish(signal, peak):
    signal = np.tanh(1.18*signal)
    sample_count = round(RATE*.039)
    signal[-sample_count:] *= .5+.5*np.cos(np.linspace(0,np.pi,sample_count))
    signal[:24] *= np.linspace(0,1,24)
    return signal * (peak/np.max(np.abs(signal)))


def write_wave(name, signal):
    assert np.isfinite(signal).all() and np.max(np.abs(signal)) < .93
    samples = np.rint(signal * 32767).astype("<i2")
    with wave.open(str(ROOT / name), "wb") as file:
        file.setparams((1, 2, RATE, len(samples), "NONE", "PCM"))
        file.writeframes(samples.tobytes())


def build():
    cue_sheet = json.loads((ROOT / "cue_sheet.json").read_text(encoding="utf-8"))
    phase = {
        "SandWarning": (warning,.43),
        "Breach": (breach,.76),
        "Bite": (bite,.64),
        "Burrow": (burrow,.51),
    }
    lead_in = .12
    attack = np.zeros(round(3.75*RATE))
    offset = 0
    for clip in cue_sheet["sequence"]:
        for name, cue in clip["cues"].items():
            generator, peak = phase[name]
            rng = np.random.default_rng(1103+319*list(phase).index(name))
            signal = finish(generator(rng),peak)
            write_wave(cue["file"],signal)
            add(attack,lead_in+offset+cue["markerSeconds"],signal,1)
            print(f'{name} {offset+cue["markerSeconds"]:.2f} s')
        offset += clip["durationSeconds"]
    write_wave("sandwurm_hoerprobe.wav",attack)


if __name__ == "__main__":
    build()
