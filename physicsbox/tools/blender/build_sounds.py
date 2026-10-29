"""Synthesises the game's sound effects inside Blender (numpy + Blender's
audio module `aud` for writing the files) into assets/sounds/*.wav.

Run:  blender -b --python tools/blender/build_sounds.py

Every sound is built from short, sharp layers - a transient crack, a body
and resonant modes - instead of long filtered noise (which reads as water),
then placed in a small room with a synthetic convolution reverb.
The shotgun shot (shotgun_shot.wav) is a recorded sample and is left alone;
the pistol shots and glass breaks are cut from real recordings by
build_recorded_sounds.py.
"""
import os

import aud
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "sounds")
SR = 44100
rng = np.random.default_rng(1911)


# ---------------------------------------------------------------- DSP helpers

def n_samples(dur):
    return int(SR * dur)


def t_axis(dur):
    return np.arange(n_samples(dur)) / SR


def noise(dur):
    return rng.standard_normal(n_samples(dur))


def band(x, lo=None, hi=None, order=2):
    """Zero-phase band limiting in the frequency domain (apply envelopes after)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR) + 1e-6
    h = np.ones_like(f)
    if hi:
        h *= 1 / (1 + (f / hi) ** (2 * order))
    if lo:
        h *= (f / lo) ** (2 * order) / (1 + (f / lo) ** (2 * order))
    return np.fft.irfft(spec * h, len(x))


def env(dur, attack, decay, hold=0.0):
    """Linear attack (s), optional hold, exponential decay (time constant, s)."""
    t = t_axis(dur)
    e = np.exp(-np.maximum(t - attack - hold, 0) / decay)
    a = max(n_samples(attack), 1)
    e[:a] *= np.linspace(0, 1, a)
    return e


def modes(dur, freqs, decays, gains, jitter=0.0):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for f, d, g in zip(freqs, decays, gains):
        f = f * (1 + rng.uniform(-jitter, jitter))
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d) * g
    a = n_samples(0.0005)
    out[:a] *= np.linspace(0, 1, a)
    return out


def at(x, delay, total):
    out = np.zeros(n_samples(total))
    i = n_samples(delay)
    m = min(len(x), len(out) - i)
    if m > 0:
        out[i:i + m] += x[:m]
    return out


def fit(x, total):
    out = np.zeros(n_samples(total))
    m = min(len(x), len(out))
    out[:m] = x[:m]
    return out


def room_ir(rt60=0.8, damp=4000.0, early=((0.009, 0.5), (0.015, 0.35), (0.023, 0.3), (0.031, 0.2)), dur=None):
    """Synthetic room impulse response: early reflections + damped diffuse tail."""
    dur = dur or rt60 * 1.1
    t = t_axis(dur)
    tail = band(noise(dur), 120, damp) * np.exp(-t * 6.91 / rt60)
    # high frequencies die out faster
    tail = 0.6 * tail + 0.4 * band(tail, None, damp * 0.4)
    tail *= np.minimum(t / 0.012, 1.0)
    ir = tail * 0.25
    ir[0] = 1.0
    for d, g in early:
        ir[n_samples(d)] += g * rng.choice([-1, 1])
    return ir


def convolve(x, ir):
    n = len(x) + len(ir)
    size = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return y


def place(dry, wet_gain, ir):
    wet = convolve(dry, ir)
    wet -= dry  # keep the dry path separate so the gain is meaningful
    return dry + wet * wet_gain


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    x -= np.mean(x)
    m = np.max(np.abs(x)) or 1.0
    x = np.tanh(x / m * 1.15) / np.tanh(1.15) * peak
    fade = n_samples(0.01)
    x[-fade:] *= np.linspace(1, 0, fade)
    buf = aud.Sound.buffer(x.astype(np.float32).reshape(-1, 1), SR)
    path = os.path.join(OUT, name + ".wav")
    buf.write(path, rate=SR, channels=aud.CHANNELS_MONO, format=aud.FORMAT_S16,
              container=aud.CONTAINER_WAV, codec=aud.CODEC_PCM)
    print("wrote", name, "%.2fs" % (len(x) / SR))


# ---------------------------------------------------------------- sounds

def concrete_hit(seed):
    total = 0.45
    crack = band(noise(0.02), 2000, 11000) * env(0.02, 0.0001, 0.0018)
    body = band(noise(0.06), 450 + seed * 120, 3200) * env(0.06, 0.0002, 0.011) * 0.8
    knock = modes(0.08, [380 + seed * 60, 910], [0.012, 0.007], [0.4, 0.2])
    dry = fit(crack, total) + fit(body, total) + fit(knock, total)
    for _ in range(7):  # falling grit
        tick = band(noise(0.01), 3000, 9000) * env(0.01, 0.0001, 0.0015) * rng.uniform(0.05, 0.18)
        dry += at(tick, rng.uniform(0.02, 0.2), total)
    return place(dry, 0.15, room_ir(0.35, 5000))


def wood_hit():
    total = 0.4
    click = band(noise(0.01), 1200, 7000) * env(0.01, 0.0001, 0.0015)
    body = modes(0.25, [185, 430, 880, 1530], [0.028, 0.016, 0.01, 0.006], [0.7, 0.45, 0.25, 0.12], 0.04)
    thud = band(noise(0.05), 100, 900) * env(0.05, 0.0003, 0.012) * 0.6
    dry = fit(click, total) + fit(body, total) + fit(thud, total)
    return place(dry, 0.18, room_ir(0.35, 4500))


def wood_break():
    total = 0.9
    dry = fit(wood_hit(), total) * 0.8
    for i in range(9):
        crack = band(noise(0.03), 900, 8000) * env(0.03, 0.0001, rng.uniform(0.002, 0.006))
        dry += at(crack * rng.uniform(0.3, 0.9), rng.uniform(0.0, 0.18), total)
        dry += at(modes(0.12, [rng.uniform(250, 600), rng.uniform(800, 1400)], [0.03, 0.015], [0.3, 0.15]),
                  rng.uniform(0.05, 0.4), total)
    return place(dry, 0.3, room_ir(0.6, 4500))


def metal_hit():
    total = 0.9
    click = band(noise(0.01), 2500, 12000) * env(0.01, 0.0001, 0.001)
    ring = modes(0.9, [612, 1717, 2951, 4420, 6150], [0.45, 0.3, 0.2, 0.12, 0.08], [0.5, 0.35, 0.25, 0.15, 0.08], 0.03)
    return place(fit(click, total) + fit(ring, total), 0.2, room_ir(0.6, 6000))


def footstep(seed):
    total = 0.25
    t = t_axis(0.08)
    heel = band(noise(0.08), 50, 380) * env(0.08, 0.001, 0.014) + np.sin(2 * np.pi * (75 + seed * 8) * t) * env(0.08, 0.001, 0.02) * 0.6
    toe = band(noise(0.03), 900, 5000) * env(0.03, 0.0005, 0.005) * 0.35
    grit = band(noise(0.08), 2500, 9000) * env(0.08, 0.002, 0.02) * 0.06
    dry = fit(heel, total) + at(toe, 0.045 + seed * 0.006, total) + at(grit, 0.04, total)
    return place(dry, 0.2, room_ir(0.35, 5000))


def dry_fire():
    total = 0.12
    a = modes(0.02, [3100, 5300, 7900], [0.004, 0.003, 0.002], [0.6, 0.35, 0.2]) + fit(band(noise(0.02), 3000, 12000) * env(0.02, 0.0001, 0.0008), 0.02) * 0.5
    b = modes(0.02, [2300, 4100], [0.004, 0.003], [0.4, 0.25])
    return fit(a, total) + at(b, 0.022, total)


def ui_click():
    total = 0.05
    tick = fit(modes(0.03, [2200, 3700], [0.004, 0.002], [0.5, 0.25]), total)
    return tick + fit(band(noise(0.01), 2000, 9000) * env(0.01, 0.0001, 0.0008) * 0.4, total)


def tinnitus():
    """Ringing in the ears after a blast or a hit: two close high tones
    beating slowly over a hiss. Every component fits a whole number of
    cycles into the clip, so it loops without a seam."""
    dur = 2.0
    t = t_axis(dur)
    x = np.sin(2 * np.pi * 3950 * t) + 0.6 * np.sin(2 * np.pi * 4121.5 * t) + 0.25 * np.sin(2 * np.pi * 7900 * t)
    hiss = band(noise(dur), 5000, 9000)
    hiss = np.roll(hiss, 0) * 0.15
    return x * (0.85 + 0.15 * np.sin(2 * np.pi * 0.5 * t)) + hiss


def heartbeat():
    """One beat as heard from inside: a low "lub" then a softer "dub"."""
    total = 0.6

    def thump(f0, dur, gain):
        t = t_axis(dur)
        f = f0 * (1.0 + 0.6 * np.exp(-t / 0.02))
        ph = 2 * np.pi * np.cumsum(f) / SR
        return np.sin(ph) * env(dur, 0.006, 0.05) * gain

    return at(thump(55, 0.25, 1.0), 0.0, total) + at(thump(68, 0.2, 0.6), 0.2, total)


def save_loop(name, x, peak=0.5):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) or 1.0) * peak
    buf = aud.Sound.buffer(x.astype(np.float32).reshape(-1, 1), SR)
    path = os.path.join(OUT, name + ".wav")
    buf.write(path, rate=SR, channels=aud.CHANNELS_MONO, format=aud.FORMAT_S16,
              container=aud.CONTAINER_WAV, codec=aud.CODEC_PCM)
    print("wrote", name, "%.2fs (loop)" % (len(x) / SR))


def main():
    os.makedirs(OUT, exist_ok=True)
    save("dry_fire", dry_fire(), 0.5)
    for i in range(2):
        save("wall_hit_%d" % i, concrete_hit(i), 0.6)
    save("wood_hit", wood_hit(), 0.6)
    save("wood_break", wood_break(), 0.75)
    save("metal_hit", metal_hit(), 0.5)
    for i in range(3):
        save("footstep_%d" % i, footstep(i), 0.32)
    save("ui_click", ui_click(), 0.45)
    save_loop("tinnitus", tinnitus(), 0.5)
    save("heartbeat", heartbeat(), 0.8)


main()
