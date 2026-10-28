"""Sounds added in 2.5: the suppressed shotgun shot and the pump-action rack.

Run: python3 make_sounds_v25.py OUT_DIR   (writes shotgun.wav and pump.wav, 22050 Hz mono 16-bit like the others)
"""
import sys, os, wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)


def lowpass(x, cut):
    # one-pole low-pass, run twice for a softer slope
    a = np.exp(-2 * np.pi * cut / SR)
    for _ in range(2):
        y = np.zeros_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def highpass(x, cut):
    return x - lowpass(x, cut)


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def write(path, x):
    x = x / (np.abs(x).max() + 1e-9) * 0.9
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def shotgun():
    """A muffled cough through the suppressor: dull low thump, gas hiss, and the clack of the action."""
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    thump = lowpass(rng.standard_normal(n), 420) * env(n, 0.002, 0.045) * 3.0
    body = np.sin(2 * np.pi * 95 * t) * env(n, 0.001, 0.06) * 0.6
    hiss = highpass(lowpass(rng.standard_normal(n), 2600), 700) * env(n, 0.004, 0.09) * 0.35
    clack = np.zeros(n)
    k = int(0.012 * SR)
    m = int(0.03 * SR)
    clack[k:k + m] = highpass(rng.standard_normal(m), 1800) * env(m, 0.0005, 0.006) * 0.5
    room = lowpass(rng.standard_normal(n), 300) * env(n, 0.03, 0.18) * 0.25
    return thump + body + hiss + clack + room


def clank(n, at, tones, decay, level):
    out = np.zeros(n)
    k = int(at * SR)
    m = n - k
    t = np.arange(m) / SR
    click = highpass(rng.standard_normal(m), 2500) * env(m, 0.0003, 0.004)
    ring = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a for f, a in tones) * env(m, 0.0005, decay)
    out[k:] = (click * 1.2 + ring * 0.5) * level
    return out


def pump():
    """Rack back (slide grinds, clank), rack forward (heavier clank)."""
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    slide = highpass(lowpass(rng.standard_normal(n), 3500), 900) * 0.12
    slide *= ((t > 0.02) & (t < 0.12)) * 1.0 + ((t > 0.2) & (t < 0.27)) * 0.8
    back = clank(n, 0.11, [(1650, 1.0), (3150, 0.6), (4400, 0.3)], 0.025, 0.9)
    fwd = clank(n, 0.27, [(1250, 1.0), (2700, 0.7), (3900, 0.3)], 0.035, 1.0)
    return lowpass(slide, 6000) + back + fwd


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    write(os.path.join(out, 'shotgun.wav'), shotgun())
    write(os.path.join(out, 'pump.wav'), pump())
    print('ok')
