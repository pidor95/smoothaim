"""Cuts real recordings (tools/sound_sources/*.mp3) into the game's sound
effects with Blender's audio module `aud`: finds each event's onset, trims
it, fades the tail out and levels it like the synthesised sounds.

Run:  blender -b --python tools/blender/build_recorded_sounds.py

Writes assets/sounds/gunshot_<n>.wav (pistol), rifle_<n>.wav (AK),
explosion_<n>.wav (grenades), blast_big.wav (FPV warhead), drone_loop.wav
(seamless loop of a quadcopter's buzz) and glass_break_<n>.wav.
"""
import os

import aud
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "tools", "sound_sources")
OUT = os.path.join(ROOT, "assets", "sounds")
SR = 44100


def load(name):
    """Recording as mono float64 at 44.1 kHz."""
    snd = aud.Sound(os.path.join(SRC, name))
    if int(snd.specs[0]) != SR:
        snd = snd.resample(SR, False)
    x = np.asarray(snd.data(), dtype=np.float64)
    return x.mean(axis=1) if x.ndim == 2 else x


def onsets(x, min_gap=0.6, rel=0.25):
    """Starts of loud events: the short-time level crossing `rel` of its max."""
    w = 441
    e = np.sqrt(np.convolve(x * x, np.ones(w) / w, "same"))
    above = e > e.max() * rel
    starts = np.where(above[1:] & ~above[:-1])[0] + 1
    if above[0]:
        starts = np.concatenate(([0], starts))
    out = []
    for s in starts:
        if not out or s - out[-1] > min_gap * SR:
            out.append(int(s))
    return out


def cut(x, start, end, fade=0.18, pre=0.004):
    a = max(int(start - pre * SR), 0)
    seg = x[a:int(min(end, len(x)))].copy()
    n = min(len(seg), int(fade * SR))
    seg[-n:] *= np.linspace(1, 0, n) ** 2
    k = int(0.002 * SR) # short fade-in: no click at the cut
    seg[:k] *= np.linspace(0, 1, k)
    return seg


def save(name, x, peak=0.9, drive=1.15):
    x = x - np.mean(x)
    m = np.max(np.abs(x)) or 1.0
    x = np.tanh(x / m * drive) / np.tanh(drive) * peak
    buf = aud.Sound.buffer(x.astype(np.float32).reshape(-1, 1), SR)
    path = os.path.join(OUT, name + ".wav")
    buf.write(path, rate=SR, channels=aud.CHANNELS_MONO, format=aud.FORMAT_S16,
              container=aud.CONTAINER_WAV, codec=aud.CODEC_PCM)
    print("wrote", name, "%.2fs" % (len(x) / SR))


def events(x, max_len, min_gap=0.6):
    starts = onsets(x, min_gap)
    for i, s in enumerate(starts):
        end = starts[i + 1] - int(0.02 * SR) if i + 1 < len(starts) else len(x)
        yield cut(x, s, min(end, s + int(max_len * SR)))


def main():
    os.makedirs(OUT, exist_ok=True)
    # pistol: three single shots of the same gun, used as random variants
    for i, seg in enumerate(events(load("pistol_shots.mp3"), 1.4)):
        save("gunshot_%d" % i, seg, 0.95, 1.4)
    # glass: four windows smashed + a shop window, all as variants
    n = 0
    for seg in events(load("glass_windows.mp3"), 1.8):
        save("glass_break_%d" % n, seg, 0.8)
        n += 1
    shop = load("glass_shop_window.mp3")
    save("glass_break_%d" % n, cut(shop, onsets(shop)[0], len(shop)), 0.8)
    # AK: single shots further into the recording (the start is a burst)
    rifle = load("rifle_shots.mp3")
    k = 0
    for s in onsets(rifle, 0.35):
        if s < 3.0 * SR:
            continue
        save("rifle_%d" % k, cut(rifle, s, s + int(0.55 * SR), fade=0.25), 0.95, 1.5)
        k += 1
        if k == 4:
            break
    # grenade: three separate blasts with their rumble
    for i, seg in enumerate(events(load("grenade_blasts.mp3"), 2.6, 1.0)):
        save("explosion_%d" % i, seg, 0.98, 1.6)
    big = load("big_blast.mp3")
    save("blast_big", cut(big, onsets(big)[0], onsets(big)[0] + int(3.2 * SR), fade=1.2), 0.98, 1.6)
    # drone: a steady stretch, its end cross-faded into its start so it loops
    dr = load("drone_flight.mp3")
    a, n_loop, xf = int(5.0 * SR), int(3.0 * SR), int(0.25 * SR)
    loop = dr[a:a + n_loop].copy()
    tail = dr[a + n_loop:a + n_loop + xf]
    ramp = np.linspace(0, 1, xf)
    loop[:xf] = loop[:xf] * ramp + tail * (1 - ramp)
    save("drone_loop", loop, 0.8, 1.0)


main()
