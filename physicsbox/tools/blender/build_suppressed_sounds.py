"""Suppressed shots (AK-74M / SVD with the PBS-1) made in Blender from the
recorded ones: the muzzle crack is mostly gone - a dull low "thup" of the
gas in the can, the clack of the bolt and a short, quiet tail.
Writes assets/sounds/rifle_sup_<n>.wav and sniper_sup_<n>.wav, and the AS Val
(val_<n>.wav): a slow 9x39 round through its built-in silencer - a deeper,
softer thump and a quicker bolt.

Run (after build_recorded_sounds.py and build_sniper_sounds.py):
  blender -b --python tools/blender/build_suppressed_sounds.py
"""
import os

import aud
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SND = os.path.join(ROOT, "assets", "sounds")
SR = 44100
rng = np.random.default_rng(545)


def load(path):
    s = aud.Sound(path).resample(SR, False)
    x = s.data()
    return x.mean(axis=1) if x.ndim > 1 else x


def lowpass(x, hz):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spec / (1 + (f / hz) ** 4), len(x))


def bandpass(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spec / (1 + (f / hi) ** 4) / (1 + (lo / np.maximum(f, 1.0)) ** 4), len(x))


def suppressed(src, length, thump_hz, bolt_at):
    x = load(src)
    total = int(length * SR)
    out = np.zeros(total)
    shot = lowpass(x, 1100.0)[:total]
    env = np.exp(-np.arange(len(shot)) / SR / 0.05)  # the boom is cut short
    out[:len(shot)] += shot * env * 0.8
    t = np.arange(int(0.12 * SR)) / SR
    thump = np.sin(2 * np.pi * (thump_hz + 60 * np.exp(-t / 0.01)) * t) * np.exp(-t / 0.035)
    out[:len(thump)] += thump * np.max(np.abs(shot)) * 0.9
    # the hiss of gas out of the can's front
    n = int(0.09 * SR)
    hiss = bandpass(rng.normal(0, 1, n), 1500, 6000) * np.exp(-np.arange(n) / SR / 0.025)
    out[:n] += hiss / (np.max(np.abs(hiss)) or 1) * np.max(np.abs(shot)) * 0.25
    # the bolt flying back and slamming home: now you hear it
    for at, gain in ((bolt_at, 0.5), (bolt_at + 0.035, 0.35)):
        m = int(0.02 * SR)
        click = bandpass(rng.normal(0, 1, m), 2000, 9000) * np.exp(-np.arange(m) / SR / 0.004)
        k = int(at * SR)
        out[k:k + m] += click / (np.max(np.abs(click)) or 1) * np.max(np.abs(shot)) * gain
    out *= np.minimum(1.0, np.linspace(6.0, 0.0, total))
    return out


def save(name, x, peak):
    x = x - np.mean(x)
    x = np.tanh(x / (np.max(np.abs(x)) or 1.0) * 1.2) / np.tanh(1.2) * peak
    buf = aud.Sound.buffer(x.astype(np.float32).reshape(-1, 1), SR)
    buf.write(os.path.join(SND, name + ".wav"), rate=SR, channels=aud.CHANNELS_MONO, format=aud.FORMAT_S16,
              container=aud.CONTAINER_WAV, codec=aud.CODEC_PCM)
    print("wrote", name)


for i in range(4):
    save("rifle_sup_%d" % i, suppressed(os.path.join(SND, "rifle_%d.wav" % i), 0.45, 140.0, 0.018), 0.7)
for i in range(3):
    save("sniper_sup_%d" % i, suppressed(os.path.join(SND, "sniper_%d.wav" % i), 0.6, 95.0, 0.03), 0.8)
for i in range(4):
    save("val_%d" % i, suppressed(os.path.join(SND, "rifle_%d.wav" % i), 0.32, 105.0, 0.012), 0.55)
