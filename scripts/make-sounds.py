#!/usr/bin/env python3
"""Placeholder sounds for Shutterlink's feedback (docs/design/04-motion-sound-haptics.md §4; Feedback.swift).

Synthesised, not recorded: band-passed noise bursts with a (1 - t)^2 decay and sine tones with a linear pitch
ramp, 10 ms attack and exponential release, through a gain x3.2 + compressor master chain (threshold -10 dB,
knee 6, ratio 12, attack 2 ms, release 120 ms). Each is then cut to its length (short raised-cosine fade) and
scaled to its peak level. All under 400 ms. Replace with recordings when there are some.

Usage: python3 scripts/make-sounds.py   (writes Shutterlink/Sounds/sfx-*.caf; needs macOS afconvert)
"""
import math, random, struct, sys, wave, pathlib, subprocess, tempfile

SR = 48000
random.seed(7)

# ---------------------------------------------------------------- Web Audio building blocks

def biquad(x, kind, freq, q):
    """BiquadFilterNode coefficients as the Web Audio spec defines them (Audio EQ Cookbook)."""
    w0 = 2 * math.pi * freq / SR
    cw, sw = math.cos(w0), math.sin(w0)
    if kind == "bandpass":
        alpha = sw / (2 * q)
        b0, b1, b2 = alpha, 0.0, -alpha
    elif kind == "highpass":
        alpha = sw / (2 * 10 ** (q / 20))           # Web Audio treats Q of low/high-pass in dB
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:
        raise ValueError(kind)
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for v in x:
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        y.append(o); x2, x1, y2, y1 = x1, v, y1, o
    # the filter keeps ringing after the buffer ends
    for _ in range(int(0.03 * SR)):
        o = b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        y.append(o); x2, x1, y2, y1 = x1, 0.0, y1, o
    return y


def noise(t0, dur, freq, q, gain, kind="bandpass"):
    n = int(SR * dur)
    buf = [(random.random() * 2 - 1) * (1 - i / n) ** 2 for i in range(n)]
    return t0, [v * gain for v in biquad(buf, kind, freq, q)]


def tone(t0, dur, f0, f1, gain, kind="sine"):
    n = int(SR * (dur + 0.02))
    out, phase = [], 0.0
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * min(1.0, t / dur)
        dt = f / SR
        if kind == "sine":
            s = math.sin(2 * math.pi * phase)
        else:                                       # band-limited sawtooth (polyBLEP), like the oscillator node
            s = 2 * phase - 1
            if phase < dt: p = phase / dt; s -= p + p - p * p - 1
            elif phase > 1 - dt: p = (phase - 1) / dt; s -= p * p + p + p + 1
        # gain: 0 → gain over 10 ms, then exponential to 0.0001 at dur
        if t < 0.01: g = gain * t / 0.01
        elif t < dur: g = gain * (0.0001 / gain) ** ((t - 0.01) / (dur - 0.01))
        else: g = 0.0001
        out.append(s * g)
        phase = (phase + dt) % 1.0
    return t0, out


def render(parts):
    end = max(int(t0 * SR) + len(x) for t0, x in parts)
    mix = [0.0] * end
    for t0, x in parts:
        at = int(t0 * SR)
        for i, v in enumerate(x): mix[at + i] += v
    return master(mix)


def master(x):
    """Gain x3.2 then DynamicsCompressorNode(threshold -10, knee 6, ratio 12, attack 2 ms, release 120 ms),
    including the node's automatic make-up gain."""
    thr, knee, ratio = -10.0, 6.0, 12.0

    def curve(db_in):                                # static curve with a soft knee, in dB
        if db_in < thr - knee / 2: return db_in
        if db_in > thr + knee / 2: return thr + (db_in - thr) / ratio
        d = db_in - thr + knee / 2
        return db_in + (1 / ratio - 1) * d * d / (2 * knee)

    makeup = 10 ** ((-curve(0.0)) * 0.6 / 20)       # the spec's (1 / full-range gain)^0.6
    att, rel = math.exp(-1 / (0.002 * SR)), math.exp(-1 / (0.12 * SR))
    env, out = 0.0, []
    for v in x:
        v *= 3.2
        lvl = abs(v)
        env = att * env + (1 - att) * lvl if lvl > env else rel * env + (1 - rel) * lvl
        if env > 1e-6:
            db_in = 20 * math.log10(env)
            g = 10 ** ((curve(db_in) - db_in) / 20)
        else:
            g = 1.0
        out.append(v * g * makeup)
    # trim the silent tail
    last = max((i for i, v in enumerate(out) if abs(v) > 1e-4), default=0)
    return out[: last + int(0.005 * SR)]


# ---------------------------------------------------------------- the six sounds

sounds = {
    # A dry lens-ring click.
    "tick":    render([noise(0, 0.03, 3000, 1.5, 0.22), tone(0, 0.025, 2400, 1800, 0.05)]),
    # A leaf shutter: closes, opens 45 ms later.
    "shutter": render([noise(0, 0.03, 1900, 1.2, 0.22), noise(0.045, 0.035, 1300, 1.2, 0.16)]),
    # Exposure start: a short rising tone; stop: falling.
    "start":   render([tone(0, 0.22, 520, 880, 0.07)]),
    "stop":    render([tone(0, 0.22, 880, 520, 0.07)]),
    # Series complete: two bell partials.
    "chime":   render([tone(0, 0.32, 660, 660, 0.07), tone(0.11, 0.3, 990, 990, 0.06)]),
    # Connected: two notes up a fifth.
    "connect": render([tone(0, 0.16, 587, 587, 0.07), tone(0.12, 0.22, 880, 880, 0.07)]),
}

PEAK_DBFS = {"tick": -24, "shutter": -14, "start": -20, "stop": -20, "chime": -18, "connect": -18}
LENGTH_MS = {"tick": 15, "shutter": 90, "start": 240, "stop": 240, "chime": 380, "connect": 360}
for name, x in sounds.items():
    n = int(SR * LENGTH_MS[name] / 1000)
    if len(x) > n:
        fade = min(int(0.004 * SR), n // 3)
        x = x[:n]
        for i in range(fade):
            x[n - fade + i] *= 0.5 * (1 + math.cos(math.pi * (i + 1) / fade))
    k = 10 ** (PEAK_DBFS[name] / 20) / max(abs(v) for v in x)
    sounds[name] = [v * k for v in x]

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "Shutterlink" / "Sounds"
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    for name, x in sounds.items():
        wav = pathlib.Path(tmp) / f"sfx-{name}.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", str(wav), str(out / f"sfx-{name}.caf")], check=True)
        peak = max(abs(v) for v in x)
        print(f"sfx-{name}: {len(x) / SR * 1000:.0f} ms, peak {20 * math.log10(peak):.1f} dBFS")
