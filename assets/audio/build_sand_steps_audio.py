"""Build original heel, tread, and grit sounds for the five sand types."""

from dataclasses import dataclass
import json
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

import numpy as np

from build_discovery_audio import ROOT, RATE, WAV_FORMAT, add, band, edge_fade, fade_in, master, timebase, write_wave


OUT = ROOT / "sand_steps"
VARIANTS = 3


@dataclass(frozen=True)
class Sand:
    duration: float
    heel_hz: int
    cutoffs: tuple[int, int]
    scrape_seconds: float
    heel_gain: float
    little_grains: int
    grain_gain: float


SURFACES = {
    "yellow": Sand(.284, 132, (370, 4600), .055, .38, 6, .13),
    "red": Sand(.322, 106, (235, 2480), .071, .57, 4, .10),
    "white": Sand(.277, 156, (680, 7200), .050, .25, 7, .12),
    "crystal": Sand(.309, 168, (990, 8800), .040, .28, 12, .33),
    "black": Sand(.314, 106, (225, 3250), .070, .63, 6, .17),
}


def build_step(surface, rng):
    duration = surface.duration + rng.uniform(-.018, .020)
    t = timebase(duration)
    hz = surface.heel_hz * rng.uniform(.92, 1.12)
    heel = np.sin(2*np.pi*(hz*t - 77*t*t)) * np.exp(-t/.023)
    heel += .34 * band(t, rng, 78, surface.cutoffs[0]+380) * np.exp(-t/.026)
    scuff = band(t, rng, *surface.cutoffs) * fade_in(t, .018)
    scuff *= np.exp(-t/surface.scrape_seconds)
    step = surface.heel_gain * heel * fade_in(t, .004) + .43*scuff

    toe_t = timebase(.155)
    toe = band(toe_t, rng, *surface.cutoffs)
    toe *= fade_in(toe_t,.008) * np.exp(-toe_t/(surface.scrape_seconds*.68))
    add(step, rng.uniform(.048,.078), toe, .32)

    for at in sorted(rng.uniform(.012,.137,surface.little_grains)):
        grain_t = timebase(rng.uniform(.012,.034))
        click = band(grain_t,rng,surface.cutoffs[0]*1.3,surface.cutoffs[1]*1.15)
        click *= fade_in(grain_t,.002) * np.exp(-grain_t/.006)
        edge_fade(click,.001,.005)
        add(step,float(at),click,surface.grain_gain*rng.uniform(.43,1.35))

    edge_fade(step,.0045,.033)
    return master(step,rng.uniform(.41,.48))


def build():
    OUT.mkdir(exist_ok=True)
    start = .12
    preview = np.zeros(round(RATE*7.85))
    groups = []
    for index,(sand_id, surface) in enumerate(SURFACES.items()):
        group = {"sandTypeId":sand_id, "takes":[]}
        for variant in range(VARIANTS):
            wave = build_step(surface,np.random.default_rng(43321+index*877+variant*12221))
            file = f"step_{sand_id}_{variant+1:02}.wav"
            write_wave(OUT/file,wave)
            at = round(start+variant*.382,3)
            add(preview,at,wave)
            group["takes"].append({"file":file,"sampleCount":len(wave),"previewAtSeconds":at})
        groups.append(group)
        start += 1.57

    write_wave(OUT/"sandschritte_hoerprobe.wav",preview)
    sheet = {"format":WAV_FORMAT,"surfaces":groups}
    (OUT/"cue_sheet.json").write_text(json.dumps(sheet,indent=2)+"\n",encoding="utf-8")
    members = ["cue_sheet.json",*(take["file"] for group in groups for take in group["takes"])]
    with ZipFile(OUT/"DuneBaron_SandSteps_SFX.zip","w") as archive:
        for name in members:
            path = OUT/name
            info = ZipInfo(path.name)
            archive.writestr(info,path.read_bytes(),compress_type=ZIP_DEFLATED)
    print(f"{len(groups)*VARIANTS} steps with a material comparison")


if __name__ == "__main__":
    build()
