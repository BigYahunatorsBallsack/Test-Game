"""Synthesize the original crate cues and their timed listening preview."""

import json
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent
RATE = 48_000
MATERIALS = {
    "wood": {
        "body": ((183, .68, .037), (313, .32, .026), (612, .17, .016), (946, .08, .012)),
        "rattle": (260, 2900), "tail": .19, "shivers": (.036, .069),
        "reveal": (0.53, .43),
    },
    "iron": {
        "body": ((120, .70, .060), (453, .41, .072), (1067, .23, .050), (1973, .105, .033)),
        "rattle": (510, 4100), "tail": .30, "shivers": (.032, .085),
        "reveal": (0.73, .51),
    },
    "gold": {
        "body": ((226, .40, .050), (711, .54, .069), (1643, .25, .065), (2413, .10, .037)),
        "rattle": (620, 5000), "tail": .24, "shivers": (.030, .063),
        "reveal": (0.99, .64),
    },
    "event": {
        "body": ((149, .60, .061), (544, .34, .047), (1321, .22, .055), (2203, .11, .037)),
        "rattle": (390, 3700), "tail": .30, "shivers": (.043, .091),
        "reveal": (1.19, .68),
    },
}


def seconds(duration):
    return np.arange(round(duration * RATE)) / RATE


def decay(t, attack, release):
    return np.minimum(t / attack, 1) * np.exp(-t / release)


def add(target, offset, source, gain=1):
    start = round(offset * RATE)
    count = min(len(source), len(target) - start)
    target[start : start + count] += source[:count] * gain


def resonances(t, modes, attack, pitch=1):
    voice = np.zeros_like(t)
    for hz, gain, release in modes:
        voice += gain * np.sin(2 * np.pi * hz * pitch * t) * decay(t, attack, release)
    return voice


def grain(t, rng, lower, upper):
    spectrum = np.fft.rfft(rng.standard_normal(len(t)))
    hz = np.fft.rfftfreq(len(t), 1 / RATE)
    band = (hz / (hz + lower)) ** 3 / (1 + (hz / upper) ** 4)
    signal = np.fft.irfft(spectrum * band, n=len(t))
    return signal / max(float(np.sqrt(np.mean(signal**2))), 1e-8)


def hardware(spec, rng, closing):
    t = seconds(spec["tail"] + (.035 if closing else 0))
    body = spec["body"]
    low, high = spec["rattle"]
    sound = np.zeros_like(t)
    pitch = .77 if closing else 1
    strength = .17 if closing else .21
    add(sound, 0, resonances(t, body, .0011, pitch))
    add(sound, 0, grain(t, rng, low, high) * decay(t, .0008, .006), strength)

    # Contact and settling sound after the first hit.
    for index, offset in enumerate(spec["shivers"]):
        pulse = resonances(t, body, .001, pitch * (1.22 + index * .16))
        pulse += .11 * grain(t, rng, low * 1.5, high) * decay(t, .0009, .009)
        add(sound, offset * (.70 if closing else 1), pulse, (.28, .13)[index])

    if spec["tail"] >= .24:
        rub_t = seconds(.125)
        rub = grain(rub_t, rng, low * .5, high * .68)
        scrape = np.sin(np.pi * rub_t / .125) ** 2
        scrape *= .65 + .35 * np.sin(2 * np.pi * (35 * rub_t + 119 * rub_t**2))
        add(sound, .006, rub * scrape, .046 if closing else .067)
    return sound


def chime(hz, instrument, lifetime):
    t = seconds(lifetime)
    partials = {
        "wood": ((1, .80, .078), (2.11, .14, .027), (3.21, .055, .017)),
        "iron": ((1, .64, .115), (1.49, .19, .048), (2.85, .26, .034), (4.17, .07, .025)),
        "gold": ((1, .72, .137), (2.00, .29, .090), (2.76, .18, .048), (4.10, .075, .031)),
        "event": ((1, .64, .208), (2.01, .27, .142), (3.03, .14, .094), (4.21, .08, .062)),
    }[instrument]
    signal = resonances(t, [(hz * ratio, gain, release) for ratio, gain, release in partials], .008)
    if instrument == "event":
        signal += .12 * np.sin(2 * np.pi * hz * 1.007 * t) * decay(t, .022, .20)
    return signal


def reveal(crate, spec, rng):
    duration, _ = spec["reveal"]
    t = seconds(duration)
    sound = np.zeros_like(t)
    swell = decay(t, .015, .072 if crate in {"wood", "iron"} else .102)
    add(sound, 0, grain(t, rng, 460, 4000) * swell, .081)

    if crate == "wood":
        body = ((174, .70, .048), (272, .41, .033), (518, .17, .020))
        add(sound, 0, resonances(t, body, .002))
        notes = ((.040, 698.46, .28), (.126, 880.00, .23))
    elif crate == "iron":
        body = ((92, .57, .075), (191, .41, .073), (431, .19, .048), (1117, .18, .059))
        add(sound, 0, resonances(t, body, .002))
        add(sound, .058, resonances(t, spec["body"], .002, .60), .24)
        notes = ((.055, 587.33, .39), (.143, 880.00, .24))
    elif crate == "gold":
        body = ((147, .40, .065), (293, .21, .051), (734, .10, .035))
        add(sound, 0, resonances(t, body, .003))
        for offset, pitch in ((.015, 1.35), (.061, 1.58), (.102, 1.80)):
            add(sound, offset, resonances(t, spec["body"], .0015, pitch), .114)
        notes = ((.014, 587.33, .56), (.103, 739.99, .44), (.192, 880.00, .47), (.318, 1174.66, .47))
    else:
        up = 2 * np.pi * (138 * t + 150 * t**2)
        down = 2 * np.pi * (257 * t - 66 * t**2)
        add(sound, 0, decay(t, .021, .125) * (.67 * np.sin(up) + .22 * np.sin(down)))
        add(sound, .10, grain(t, rng, 1050, 5400) * decay(t, .060, .16), .076)
        notes = ((.021, 493.88, .43), (.112, 659.26, .48), (.228, 783.99, .39), (.341, 987.77, .55))

    for offset, hz, gain in notes:
        tone = chime(hz, crate, duration - offset)
        add(sound, offset, tone, gain)
        add(sound, offset + .097, tone, gain * .12)
    return sound


def master(signal, peak):
    signal = np.tanh(signal * 1.30)
    signal /= np.max(np.abs(signal))
    length = round(.035 * RATE)
    signal[-length:] *= .5 + .5 * np.cos(np.pi * np.linspace(0, 1, length))
    signal[:12] *= np.linspace(0, 1, 12)
    return signal * peak


def wav(path, samples):
    assert np.all(np.isfinite(samples)) and max(abs(samples)) < .94
    with wave.open(str(path), "wb") as stream:
        stream.setparams((1, 2, RATE, len(samples), "NONE", "PCM"))
        stream.writeframes(np.rint(samples * 32767).astype("<i2").tobytes())


def build():
    sheet = json.loads((ROOT / "cue_sheet.json").read_text(encoding="utf-8"))
    preview = np.zeros(14 * RATE)
    time = .10
    for index, (crate, spec) in enumerate(MATERIALS.items()):
        rng = np.random.default_rng(20421 + 1729 * index)
        clips = sheet["crates"][crate]
        open_cues = clips["Open"]["cues"]
        lock_cue = clips["Close"]["cues"]["Latch"]
        cues = (
            (open_cues["Unlatch"], master(hardware(spec, rng, False), .42 + .027 * index), 0),
            (open_cues["Reveal"], master(reveal(crate, spec, rng), spec["reveal"][1]), 0),
            (lock_cue, master(hardware(spec, rng, True), .44 + .024 * index), clips["Open"]["durationSeconds"] + .36),
        )
        end = time
        for cue, signal, clip_start in cues:
            wav(ROOT / cue["file"], signal)
            start = time + clip_start + cue["markerSeconds"]
            add(preview, start, signal)
            end = max(end, start + len(signal) / RATE)
        print(f"{crate:5} {time:.3f}–{end:.3f} s")
        time = end + .37
    assert time < len(preview) / RATE
    wav(ROOT / "kisten_soundvergleich.wav", preview[:round(time * RATE)])


if __name__ == "__main__":
    build()
