"""Procedurally synthesises the game's sound effects into assets/sounds/*.wav.

The shotgun shot (shotgun_shot.wav) is a recorded sample and are not generated here.

Run: python3 tools/gen_sounds.py  (needs numpy)
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(1911)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    # one-pole low pass
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(dur, attack, decay_rate):
    t = t_axis(dur)
    e = np.exp(-t * decay_rate)
    a = int(SR * attack)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def pad(x, dur):
    n = int(SR * dur)
    out = np.zeros(max(n, len(x)))
    out[: len(x)] = x
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, delay):
    return np.concatenate([np.zeros(int(SR * delay)), x])


def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = np.tanh(x / peak * 1.4) / np.tanh(1.4) * gain
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, f"{len(x) / SR:.2f}s")


def click(freq, dur=0.03, decay=260, amount=1.0):
    t = t_axis(dur)
    tone = np.sin(2 * np.pi * freq * t) * 0.5 + np.sin(2 * np.pi * freq * 2.7 * t) * 0.3
    return (tone + highpass(noise(dur), 2000) * 0.8) * env(dur, 0.0005, decay) * amount


def gunshot():
    dur = 1.1
    t = t_axis(dur)
    crack = highpass(noise(dur), 1500) * env(dur, 0.0003, 70)
    body = lowpass(noise(dur), 900) * env(dur, 0.001, 14) * 1.4
    sweep = np.sin(2 * np.pi * (140 * t - 60 * t * t)) * env(dur, 0.001, 22) * 1.3
    tail = lowpass(noise(dur), 400) * env(dur, 0.02, 5) * 0.5
    mech = at(click(2400, 0.04, 200, 0.35), 0.035)
    return mix(crack * 1.2, body, sweep, tail, mech)


def dry_fire():
    return mix(click(3200, 0.05, 300, 0.8), at(click(1800, 0.04, 260, 0.4), 0.02))


def wall_hit(variant):
    dur = 0.3
    t = t_axis(dur)
    chip = highpass(noise(dur), 2500) * env(dur, 0.0005, 60)
    knock = np.sin(2 * np.pi * (220 + 60 * variant) * t) * env(dur, 0.0005, 45) * 0.8
    debris = mix(*[at(highpass(noise(0.02), 3000) * env(0.02, 0.0005, 200) * 0.3, d)
                   for d in rng.uniform(0.03, 0.2, 6)])
    return mix(chip, knock, debris)


def wood_hit():
    dur = 0.3
    t = t_axis(dur)
    knock = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(310, 0.7), (720, 0.4), (1300, 0.2)]) * env(dur, 0.0005, 35)
    return mix(knock, highpass(noise(dur), 1500) * env(dur, 0.0005, 80) * 0.5)


def metal_hit():
    dur = 0.7
    t = t_axis(dur)
    ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(820, 0.5), (1910, 0.35), (3350, 0.25), (5020, 0.15)]) * env(dur, 0.0005, 9)
    return mix(ring, highpass(noise(dur), 3000) * env(dur, 0.0005, 90) * 0.6)


def glass_break():
    dur = 1.0
    parts = [highpass(noise(dur), 2500) * env(dur, 0.0005, 18) * 0.7]
    for d in np.cumsum(rng.uniform(0.01, 0.06, 22)):
        f = rng.uniform(2500, 7000)
        tt = t_axis(0.12)
        parts.append(at(np.sin(2 * np.pi * f * tt) * env(0.12, 0.0005, 40) * rng.uniform(0.15, 0.5), d))
    return mix(*parts)


def footstep(variant):
    dur = 0.18
    t = t_axis(dur)
    return mix(lowpass(noise(dur), 900 + 200 * variant) * env(dur, 0.003, 40),
               np.sin(2 * np.pi * (80 + 10 * variant) * t) * env(dur, 0.002, 50) * 0.5)


def ui_click():
    return click(1500, 0.05, 160, 0.6)


def hitmarker():
    t = t_axis(0.07)
    return np.sin(2 * np.pi * 2300 * t) * env(0.07, 0.0005, 70) * 0.6 + highpass(noise(0.07), 4000) * env(0.07, 0.0005, 120) * 0.3


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("gunshot", gunshot(), 0.95)
    save("dry_fire", dry_fire(), 0.6)
    for i in range(2):
        save(f"wall_hit_{i}", wall_hit(i), 0.6)
    save("wood_hit", wood_hit(), 0.6)
    save("metal_hit", metal_hit(), 0.55)
    save("glass_break", glass_break(), 0.8)
    for i in range(3):
        save(f"footstep_{i}", footstep(i), 0.35)
    save("ui_click", ui_click(), 0.5)
    save("hitmarker", hitmarker(), 0.5)
