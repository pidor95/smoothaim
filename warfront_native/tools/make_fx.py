"""Synthesise the game's sound effects (WAV) and particle sprites (PNG) so no third-party assets are needed.

Run: python3 make_fx.py OUT_DIR   (writes sounds/*.wav and fx/*.png)
"""
import sys, os, wave
import numpy as np
from PIL import Image

OUT = sys.argv[1]
SR = 22050
rng = np.random.default_rng(3)
os.makedirs(os.path.join(OUT, 'sounds'), exist_ok=True)
os.makedirs(os.path.join(OUT, 'fx'), exist_ok=True)


def save(name, x, loop=False):
    x = np.asarray(x, np.float64)
    if loop:  # crossfade the ends so the loop has no click
        n = SR // 10
        x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
        x = x[:-n]
    x = x / (np.abs(x).max() + 1e-9) * 0.9
    with wave.open(os.path.join(OUT, 'sounds', name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def noise(n):
    return rng.standard_normal(n)


def lowpass(x, a):
    y = np.empty_like(x); s = 0.0
    for i, v in enumerate(x):
        s += a * (v - s); y[i] = s
    return y


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(t / max(attack, 1e-4), 1) * np.exp(-t / decay)


t = lambda d: np.arange(int(SR * d)) / SR
# engines (looped)
d = 2.1
save('jet', lowpass(noise(int(SR * d)), .25) * .8 + lowpass(noise(int(SR * d)), .03) * 2 + np.sin(2 * np.pi * 180 * t(d)) * .05, True)
x = t(2.1); blade = (np.sin(2 * np.pi * 4.5 * x) > .55).astype(float)
save('heli', lowpass(noise(len(x)), .08) * (0.4 + blade * 1.4) + np.sin(2 * np.pi * 45 * x) * .3 * (0.6 + blade), True)
x = t(2.1)
save('tank', lowpass(noise(len(x)), .05) * 1.5 + np.sign(np.sin(2 * np.pi * 32 * x)) * .25 + np.sin(2 * np.pi * 64 * x) * .2, True)
# weapons
n = int(SR * .12); save('gun', lowpass(noise(n), .5) * env(n, .001, .03) + np.sin(2 * np.pi * 120 * t(.12)) * env(n, .001, .04) * .6)
n = int(SR * .2); save('mg', lowpass(noise(n), .6) * env(n, .001, .025))
n = int(SR * 1.6); save('cannon', lowpass(noise(n), .12) * env(n, .002, .35) + np.sin(2 * np.pi * 55 * t(1.6)) * env(n, .002, .25) * 1.2)
n = int(SR * 2.4); save('explosion', lowpass(noise(n), .06) * env(n, .005, .6) * 1.5 + lowpass(noise(n), .4) * env(n, .001, .08))
n = int(SR * 1.2); save('missile', lowpass(noise(n), .35) * env(n, .05, .5))
n = int(SR * .5); save('rocket', lowpass(noise(n), .45) * env(n, .01, .2))
n = int(SR * .4); save('flare', lowpass(noise(n), .7) * env(n, .005, .12) + np.sin(2 * np.pi * 1800 * t(.4)) * env(n, .001, .03) * .3)
n = int(SR * 1.5); save('smoke', lowpass(noise(n), .2) * env(n, .03, .5))
n = int(SR * .4); save('hit', lowpass(noise(n), .5) * env(n, .001, .05) + np.sin(2 * np.pi * 900 * t(.4)) * env(n, .001, .04) * .5)
# cockpit tones
x = t(.07); save('beep', np.sin(2 * np.pi * 880 * x) * np.minimum(1, (len(x) - np.arange(len(x))) / 200))
x = t(.5); save('lock', np.sin(2 * np.pi * 1760 * x), True)
x = t(.09); save('warn', np.sign(np.sin(2 * np.pi * 1250 * x)) * .6 * np.minimum(1, (len(x) - np.arange(len(x))) / 200))
x = t(.05); save('click', np.sin(2 * np.pi * 700 * x) * np.exp(-x / .015))

# sprites
S = 128
yy, xx = np.mgrid[0:S, 0:S] / (S - 1) * 2 - 1
r = np.sqrt(xx ** 2 + yy ** 2)


def fbm(seed, oct=5):
    g = np.random.default_rng(seed); out = np.zeros((S, S))
    for o in range(oct):
        p = 4 << o; base = g.random((p + 1, p + 1))
        ix = np.linspace(0, p, S); i0 = np.floor(ix).astype(int).clip(0, p - 1); f = ix - i0
        f = f * f * (3 - 2 * f)
        a = base[i0][:, i0] * (1 - f)[None, :] + base[i0][:, i0 + 1] * f[None, :]
        b = base[i0 + 1][:, i0] * (1 - f)[None, :] + base[i0 + 1][:, i0 + 1] * f[None, :]
        out += (a * (1 - f)[:, None] + b * f[:, None]) / (2 ** o)
    return out / out.max()


n = fbm(5)
puff = np.clip(1 - r, 0, 1) ** 1.2 * (0.55 + 0.6 * n)
alpha = np.clip(puff * 1.6 - 0.15, 0, 1)
shade = 0.75 + 0.25 * np.clip(-yy * 0.6 + n * 0.6, 0, 1)
img = np.dstack([shade, shade, shade, alpha])
Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(OUT, 'fx', 'smoke.png'))
fire = np.clip(1 - r, 0, 1) ** 1.6 * (0.6 + 0.5 * fbm(9))
Image.fromarray((np.dstack([np.ones_like(r), np.ones_like(r), np.ones_like(r), np.clip(fire * 1.4, 0, 1)]) * 255).astype(np.uint8)).save(os.path.join(OUT, 'fx', 'fire.png'))
glow = np.clip(1 - r, 0, 1) ** 2.5
Image.fromarray((np.dstack([np.ones_like(r)] * 3 + [glow]) * 255).astype(np.uint8)).save(os.path.join(OUT, 'fx', 'glow.png'))
print('fx done')
