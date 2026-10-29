"""Sniper rifle shots (SVD, Mosin) made in Blender from the recorded AK shots:
pitched down for the heavier 7.62x54R round, a low thump under the crack
and a long rolling echo over the open field.
Writes assets/sounds/sniper_<n>.wav.

Run (after build_recorded_sounds.py):  blender -b --python tools/blender/build_sniper_sounds.py
"""
import os

import aud
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SND = os.path.join(ROOT, "assets", "sounds")
SR = 44100
rng = np.random.default_rng(762)


def load(path):
    s = aud.Sound(path).resample(SR, False)
    x = s.data()
    return x.mean(axis=1) if x.ndim > 1 else x


def lowpass(x, hz):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spec / (1 + (f / hz) ** 4), len(x))


def sniper(src):
    x = load(src)
    # 0.72x speed: lower and longer
    n = int(len(x) / 0.72)
    shot = np.interp(np.arange(n) * 0.72, np.arange(len(x)), x)
    total = int(1.9 * SR)
    out = np.zeros(total)
    out[:min(n, total)] += shot[:total]
    t = np.arange(int(0.45 * SR)) / SR
    thump = np.sin(2 * np.pi * (55 + 40 * np.exp(-t / 0.03)) * t) * np.exp(-t / 0.12)
    out[:len(thump)] += thump * np.max(np.abs(shot)) * 0.8
    # the echo rolling back off the tree lines and the houses
    dry = out.copy()
    for delay, gain, hz in ((0.16, 0.35, 2500), (0.38, 0.28, 1500), (0.7, 0.2, 900), (1.05, 0.12, 600)):
        d = int(delay * SR)
        e = lowpass(dry, hz)[:total - d] * gain
        out[d:] += e
    out *= np.minimum(1.0, np.linspace(9.0, 0.0, total))  # fade the tail
    return out


def save(name, x, peak=0.95):
    x = x - np.mean(x)
    x = np.tanh(x / (np.max(np.abs(x)) or 1.0) * 1.4) / np.tanh(1.4) * peak
    buf = aud.Sound.buffer(x.astype(np.float32).reshape(-1, 1), SR)
    buf.write(os.path.join(SND, name + ".wav"), rate=SR, channels=aud.CHANNELS_MONO, format=aud.FORMAT_S16,
              container=aud.CONTAINER_WAV, codec=aud.CODEC_PCM)
    print("wrote", name)


for i in range(3):
    save("sniper_%d" % i, sniper(os.path.join(SND, "rifle_%d.wav" % i)))
