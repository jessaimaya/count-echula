#!/usr/bin/env python3
"""Synthesize the small sound effects into game/assets/audio/sfx/ (48 kHz mono float).

    python3 scripts/make_sfx.py

burst_whoosh   rising shimmer on a color burst (~0.8 s)
gate_rattle    the portcullis chains as it starts to fall (~0.35 s)
gate_slam      the portcullis landing: a thud, an iron clang, a rattle tail (~1.2 s)
ui_tick        hover over a button (very short, soft)
ui_click       press a button
ui_flip        flip a record on the shelf (a short swish)

Seeded, so a rerun writes the same files.
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 48000
OUT = os.path.join(os.path.dirname(__file__), '..', 'game', 'assets', 'audio', 'sfx')
rng = np.random.default_rng(31)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack, release):
    """Linear attack, exponential-ish release over the last `release` seconds."""
    e = np.ones(n)
    a = max(1, int(SR * attack))
    e[:a] = np.linspace(0, 1, a)
    r = max(1, int(SR * release))
    e[-r:] *= np.linspace(1, 0, r) ** 2
    return e


def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], 'bandpass', fs=SR, output='sos'), x)


def low(x, hz, order=2):
    return sosfilt(butter(order, hz, 'lowpass', fs=SR, output='sos'), x)


def sweep_band(noise, f0, f1, steps=40):
    """Noise through a band-pass whose center glides f0 -> f1 (block-wise)."""
    out = np.zeros_like(noise)
    edges = np.linspace(0, len(noise), steps + 1).astype(int)
    for i in range(steps):
        fc = f0 * (f1 / f0) ** (i / (steps - 1))
        seg = band(noise, fc / 1.6, min(fc * 1.6, SR / 2 - 100))
        out[edges[i]:edges[i + 1]] = seg[edges[i]:edges[i + 1]]
    return out


def metal(tt, freqs, decay):
    """Inharmonic partials: an iron hit."""
    s = np.zeros_like(tt)
    for i, f in enumerate(freqs):
        s += np.sin(2 * np.pi * f * tt + rng.uniform(0, 6.28)) * np.exp(-tt * decay * (1 + 0.35 * i)) / (1 + 0.4 * i)
    return s


def norm(x, peak):
    return (x / np.max(np.abs(x)) * peak).astype(np.float32)


def write(name, x, peak):
    wavfile.write(os.path.join(OUT, name + '.wav'), SR, norm(x, peak))
    print('%-14s %.2f s' % (name, len(x) / SR))


def burst_whoosh():
    tt = t(0.8)
    n = len(tt)
    air = sweep_band(rng.standard_normal(n), 300, 7000) * env(n, 0.45, 0.3)
    # a rising shimmer: a few detuned sines gliding up an octave and a half
    f = 700 * 2 ** (1.5 * tt / tt[-1])
    phase = 2 * np.pi * np.cumsum(f) / SR
    shim = sum(np.sin(phase * k + 0.3 * k) / k for k in (1, 1.5, 2.01, 3.02))
    shim *= (0.5 + 0.5 * np.sin(2 * np.pi * 18 * tt)) * env(n, 0.5, 0.35)
    return air + 0.25 * shim


def gate_rattle():
    tt = t(0.4)
    s = np.zeros_like(tt)
    # chain links knocking, closer together as it gains speed
    at = 0.0
    gap = 0.05
    while at < 0.33:
        i = int(at * SR)
        k = t(0.06)
        hit = metal(k, rng.uniform(1, 1.3) * np.array([1250, 2310, 3570]), 70)
        hit *= rng.uniform(0.5, 1)
        s[i:i + len(k)] += hit[:len(s) - i]
        at += gap * rng.uniform(0.7, 1.2)
        gap = max(0.015, gap * 0.85)
    return s * env(len(tt), 0.01, 0.08)


def gate_slam():
    tt = t(1.2)
    n = len(tt)
    # body: a low thud with a falling pitch
    f = 45 + 50 * np.exp(-tt * 25)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 6)
    crunch = low(rng.standard_normal(n), 900) * np.exp(-tt * 30)
    # iron: the portcullis bars ringing
    clang = metal(tt, [212, 347, 529, 798, 1163], 5.5)
    # the chains settling after the hit
    rattle = np.zeros(n)
    for at in (0.12, 0.2, 0.31, 0.38, 0.5):
        i = int(at * SR)
        k = t(0.05)
        rattle[i:i + len(k)] += metal(k, rng.uniform(0.9, 1.2) * np.array([1400, 2600]), 80) * (0.6 - at * 0.8)
    return 1.0 * thud + 0.5 * crunch + 0.35 * clang + 0.25 * rattle


def ui_tick():
    tt = t(0.05)
    f = 2400 - 600 * tt / tt[-1]
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 90)


def ui_click():
    tt = t(0.12)
    f = 950 * np.exp(-tt * 14) + 300
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 38)
    snap = band(rng.standard_normal(len(tt)), 2000, 6000) * np.exp(-tt * 300)
    return body + 0.4 * snap


def ui_flip():
    tt = t(0.18)
    n = len(tt)
    return sweep_band(rng.standard_normal(n), 2500, 900, 20) * np.sin(np.pi * tt / tt[-1]) ** 2


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    # peaks sit with the existing effects (hit.wav peaks at ~0.45)
    write('burst_whoosh', burst_whoosh(), 0.4)
    write('gate_rattle', gate_rattle(), 0.35)
    write('gate_slam', gate_slam(), 0.6)
    write('ui_tick', ui_tick(), 0.18)
    write('ui_click', ui_click(), 0.35)
    write('ui_flip', ui_flip(), 0.3)
