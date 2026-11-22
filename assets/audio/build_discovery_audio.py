"""Build original find stingers and five seamless zone atmospheres."""

import json
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent
RATE = 48_000
WAV_FORMAT = {"sampleRate": RATE, "channels": 1, "sampleWidthBits": 16, "encoding": "PCM"}


def timebase(seconds):
    return np.arange(round(seconds * RATE)) / RATE


def band(t, rng, low, high):
    hz = np.fft.rfftfreq(len(t), 1 / RATE)
    window = (hz / (hz + low)) ** 2.4 / (1 + (hz / high) ** 4)
    source = np.fft.rfft(rng.standard_normal(len(t)))
    result = np.fft.irfft(source * window, n=len(t))
    return result / np.sqrt(np.mean(result**2))


def fade_in(t, seconds):
    return np.sin(np.pi * np.clip(t / seconds, 0, 1) / 2) ** 2


def roll_layer(t, rate, phase=0):
    period = len(t) / RATE
    cycles = max(1, round(rate * period))
    return np.sin(2 * np.pi * cycles * t / period + phase)


def add(signal, at, layer, gain=1):
    start = round(at * RATE)
    count = min(len(layer), len(signal) - start)
    signal[start : start + count] += gain * layer[:count]


def edge_fade(signal, attack, release):
    start, end = round(RATE * attack), round(RATE * release)
    signal[:start] *= fade_in(timebase(attack), attack)
    signal[-end:] *= fade_in(timebase(release), release)[::-1]


def master(signal, peak):
    audio = np.tanh(signal)
    return audio * (peak / np.max(np.abs(audio)))


def write_wave(file, data):
    assert np.isfinite(data).all() and np.abs(data).max() < .90
    with wave.open(str(file), "wb") as stream:
        stream.setparams((1, 2, RATE, len(data), "NONE", "PCM"))
        stream.writeframes(np.rint(data * 32767).astype("<i2").tobytes())


RARITIES = {
    "common": (.27, .33, ((.016, 392.00, .48),)),
    "uncommon": (.36, .37, ((.020, 440.00, .52), (.100, 587.33, .45))),
    "rare": (.48, .43, ((.014, 493.88, .54), (.094, 659.26, .49), (.158, 783.99, .28))),
    "epic": (.62, .47, ((.011, 440.00, .49), (.081, 523.25, .48), (.159, 659.26, .47), (.245, 987.77, .31))),
    "legendary": (.79, .53, ((.010, 392.00, .50), (.079, 493.88, .50), (.157, 587.33, .47), (.244, 783.99, .39), (.324, 1174.66, .32))),
    "mythic": (.94, .55, ((0, 146.83, .42), (.045, 440.00, .49), (.124, 587.33, .52), (.222, 698.46, .38), (.302, 880.00, .42), (.412, 1318.51, .33))),
}


def find_tone(rarity, index, rng):
    duration, peak, notes = RARITIES[rarity]
    all_times = timebase(duration)
    sound = .24 * band(all_times, rng, 675, 3500) * fade_in(all_times, .0028) * np.exp(-all_times / .019)
    sound += .27 * np.sin(2 * np.pi * 138 * all_times) * fade_in(all_times, .0045) * np.exp(-all_times / .040)
    release = .056 + .022 * index
    for when, hz, gain in notes:
        t = timebase(duration - when)
        tone = np.sin(2 * np.pi * hz * t) * np.exp(-t / release)
        overtone = .31 * np.sin(2 * np.pi * 2.01 * hz * t + .82) * np.exp(-t / (release * .57))
        shimmer = .11 * np.sin(2 * np.pi * 2.98 * hz * t + 1.17) * np.exp(-t / .047)
        phrase = (tone + overtone + shimmer) * fade_in(t, .0084)
        add(sound, when, phrase, gain)
        add(sound, when + .064, phrase, gain * (.08 + .011 * index))
    edge_fade(sound, .0025, .045)
    return master(sound, peak)


ZONES = {
    "dunes": ("duenenmeer", 20.0, 4.7),
    "oasis": ("oase", 22.0, 5.2),
    "canyon": ("canyon", 21.0, 3.5),
    "salt_lake": ("salzsee", 24.0, 4.3),
    "ruins": ("ruinenstadt", 23.0, 8.6),
}


def place_cycle(pool, at, layer, gain):
    start = round(at * RATE) % len(pool)
    head = min(len(layer), len(pool) - start)
    pool[start:start + head] += layer[:head] * gain
    pool[:len(layer) - head] += layer[head:] * gain


def accents(sound, rng, positions, color, seconds, gain, resonant=None, echo=0):
    for i, at in enumerate(positions):
        length = seconds + (i % 3) * .037
        t = timebase(length)
        grain = band(t, rng, *color)
        if resonant:
            hz = resonant * (1 + .11 * (i % 4))
            grain = .53 * grain + .47 * np.sin(2 * np.pi * (hz * t - 46 * t**2))
        grain *= fade_in(t, .013) * np.exp(-t / (length * .24))
        edge_fade(grain, .004, .022)
        strength = gain * (.71 + .22 * (i % 3))
        place_cycle(sound, at, grain, strength)
        if echo:
            place_cycle(sound, at + echo, grain, strength * .28)


def atmosphere(zone, duration, rng):
    t = timebase(duration)
    swell = .72 + .26 * roll_layer(t, .19, 1.2) + .13 * roll_layer(t, .073, .36)
    hush = band(t, rng, 66, 950) * swell
    rumble = band(t, rng, 28, 265) * (.78 + .22 * roll_layer(t, .14, .7))

    if zone == "dunes":
        flow = .52 * hush + .18 * rumble
        flow += .19 * band(t, rng, 393, 2600) * (.45 + .40 * roll_layer(t, .13, 1.9))
        accents(flow, rng, (2.12, 6.91, 13.42, 19.82), (375, 2600), .54, .12)
    elif zone == "oasis":
        drops = band(t, rng, 428, 2670)
        waves = .52 + .26 * roll_layer(t, .47, .2) + .20 * roll_layer(t, .81, 1.11)
        flow = .26 * hush + .54 * drops * waves + .16 * band(t, rng, 138, 795)
        accents(flow, rng, (1.50, 3.8, 5.99, 6.50, 8.63, 12.22, 16.77, 18.8, 21.87), (666, 3140), .138, .151, 572, .095)
        accents(flow, rng, (3.3, 10.1, 18.18), (437, 3340), .66, .10)
    elif zone == "canyon":
        tunnel = band(t, rng, 117, 632) * (.69 + .31 * roll_layer(t, .21, 2.8))
        flow = .26 * hush + .43 * tunnel + .31 * rumble
        flow += .15 * np.roll(tunnel, round(.191 * RATE)) + .07 * np.roll(tunnel, round(.335 * RATE))
        accents(flow, rng, (3.1, 6.22, 10.70, 17.2), (243, 1745), .32, .103, 172, .166)
    elif zone == "salt_lake":
        air = band(t, rng, 245, 2070) * (.62 + .28 * roll_layer(t, .18, 1.25))
        flow = .27 * hush + .12 * rumble + .38 * air
        accents(flow, rng, (2.3, 5.9, 6.76, 8.39, 12.65, 16.71, 20.2, 23.88), (719, 3800), .178, .11, 1044, .124)
    else:
        enclosed = band(t, rng, 151, 724) * (.74 + .26 * roll_layer(t, .10, 2.0))
        flow = .29 * hush + .35 * enclosed + .26 * rumble
        flow += .11 * np.roll(enclosed, round(.127 * RATE))
        accents(flow, rng, (1.72, 5.31, 9.0, 9.68, 13.76, 17.15, 21.21), (350, 2400), .268, .14, 199, .17)
    return master(flow, .41 if zone == "canyon" else .37)


def build():
    finds = ROOT / "finds"
    zones = ROOT / "zones"
    for folder in (finds, zones):
        folder.mkdir(exist_ok=True)

    listing = []
    mix = [np.zeros(round(.10 * RATE))]
    at = .10
    for i, rarity in enumerate(RARITIES):
        tone = find_tone(rarity, i, np.random.default_rng(4130 + i * 173))
        name = f"fund_{rarity}.wav"
        write_wave(finds / name, tone)
        listing.append({"rarityId": rarity, "file": name, "previewAtSeconds": round(at, 2)})
        pause = max(.22, 1.06 - len(tone) / RATE)
        mix.extend((tone, np.zeros(round(RATE * pause))))
        at += len(tone) / RATE + pause
    write_wave(finds / "fundklaenge_hoerprobe.wav", np.concatenate(mix))
    (finds / "cue_sheet.json").write_text(json.dumps({"format": WAV_FORMAT, "cues": listing}, indent=2) + "\n", encoding="utf-8")

    listing = []
    mix = [np.zeros(round(.10 * RATE))]
    piece = 4.35
    for i, (zone_id, (name, duration, sample_at)) in enumerate(ZONES.items()):
        sound = atmosphere(zone_id, duration, np.random.default_rng(9517 + i * 4321))
        file = f"ambiente_{name}.wav"
        write_wave(zones / file, sound)
        start = round(sample_at * RATE)
        snippet = sound[start:start + round(piece * RATE)].copy()
        edge_fade(snippet, .33, .43)
        mix.extend((snippet, np.zeros(round(.30 * RATE))))
        listing.append({"zoneId": zone_id, "file": file, "durationSeconds": duration,
            "previewAtSeconds": round(.10 + i * (piece + .30), 2)})
    write_wave(zones / "zonen_hoervergleich.wav", np.concatenate(mix))
    (zones / "cue_sheet.json").write_text(json.dumps({"format": WAV_FORMAT, "loops": listing}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
