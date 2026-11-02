#!/usr/bin/env python3
"""Small assets: a white texture for markers and synthesized sound effects (WAV, 44.1 kHz mono)."""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SR = 44100


def write_wav(path: Path, sig: np.ndarray):
    path.parent.mkdir(parents=True, exist_ok=True)
    sig = sig / (np.abs(sig).max() + 1e-9) * 0.9
    data = (sig * 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"  {path.relative_to(ROOT)}  {len(sig) / SR:.2f} s")


def knock_hit(dur=0.18, f0=180.0, seed=0) -> np.ndarray:
    """One knuckle-on-wood knock: damped low modes plus a short noise click."""
    r = np.random.default_rng(seed)
    t = np.arange(int(SR * dur)) / SR
    body = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d)
               for a, f, d in ((1.0, f0, 38), (0.6, f0 * 2.3, 55), (0.35, f0 * 3.9, 80)))
    click = r.normal(0, 1, len(t)) * np.exp(-t * 400) * 0.6
    return body + click


def knock() -> np.ndarray:
    gap = np.zeros(int(SR * 0.09))
    return np.concatenate([knock_hit(seed=1), gap, knock_hit(f0=170, seed=2) * 0.9, np.zeros(int(SR * 0.1))])


def slam() -> np.ndarray:
    """Tile slammed on the table: heavier thump with rattle."""
    r = np.random.default_rng(5)
    t = np.arange(int(SR * 0.7)) / SR
    thump = np.sin(2 * np.pi * 95 * t) * np.exp(-t * 14) + 0.5 * np.sin(2 * np.pi * 61 * t) * np.exp(-t * 10)
    crack = r.normal(0, 1, len(t)) * np.exp(-t * 90)
    rattle = np.zeros_like(t)
    for k in range(9):
        start = int(SR * (0.05 + 0.045 * k + r.uniform(0, 0.02)))
        hit = knock_hit(0.06, 900 + r.uniform(-200, 300), seed=10 + k) * (0.35 * 0.8 ** k)
        rattle[start:start + len(hit)] += hit[: len(rattle) - start]
    return thump * 1.2 + crack * 0.5 + rattle


def spin() -> np.ndarray:
    """Tile spinning on its nub: a whirring rattle that slows down."""
    dur = 2.4
    t = np.arange(int(SR * dur)) / SR
    rate = 28 * (1 - t / dur) ** 1.3 + 2
    phase = np.cumsum(rate) / SR
    ticks = (np.sin(2 * np.pi * phase) > 0.97).astype(float)
    r = np.random.default_rng(9)
    tone = np.convolve(ticks, np.exp(-np.arange(300) / 40) * r.normal(0, 1, 300), mode="same")
    return tone * (1 - t / dur) ** 0.5


def main():
    img = Image.new("RGB", (64, 64), (255, 255, 255))
    p = ROOT / "assets/textures/white.png"
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p)
    print("  assets/textures/white.png")
    write_wav(ROOT / "assets/sounds/knock.wav", knock())
    write_wav(ROOT / "assets/sounds/slam.wav", slam())
    write_wav(ROOT / "assets/sounds/spin.wav", spin())


if __name__ == "__main__":
    main()
