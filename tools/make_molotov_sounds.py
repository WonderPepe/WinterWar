"""Cuts the Molotov cocktail sounds (T2) out of the owner's downloads (not part of the game).
Run from the project folder:  python3 tools/make_molotov_sounds.py   (needs ffmpeg + numpy)
Writes to assets/audio/recorded/ (RecordedSounds finds them by name):

  assets_source/molotov_break….wav  Freesound 74899 by Benboncan     -> molotov_break.ogg  (glass + whoosh)
  assets_source/molotov_ignite….wav Freesound 379108 by AdamsArchive -> molotov_ignite.ogg (match / lighter)
  assets_source/molotov_throw.mp3   Freesound 683101 by florianreichelt (CC0) -> molotov_throw.ogg
  assets_source/fire_loop.wav       Freesound 564621 by Nox_Sound (CC0)        -> fire_loop.ogg (loop)
"""
import glob
import os
import subprocess

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets_source")
DST = os.path.join(ROOT, "assets", "audio", "recorded")
SR = 44100


def load(pattern: str) -> np.ndarray:
    hits = glob.glob(os.path.join(SRC, pattern))
    if not hits:
        raise SystemExit(f"missing assets_source/{pattern}")
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", hits[0], "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def save(x: np.ndarray, name: str, peak_db: float) -> None:
    x = x / max(np.abs(x).max(), 1e-9) * 10 ** (peak_db / 20.0)
    path = os.path.join(DST, name)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f64le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", path], input=x.tobytes(), check=True)
    print(f"{name}: {len(x) / SR:.2f} s, {os.path.getsize(path) / 1000:.0f} kB")


def cut(x: np.ndarray, start: float, length: float, fade_from: float) -> np.ndarray:
    a = int(start * SR)
    y = x[a:a + int(length * SR)].copy()
    n = int(0.003 * SR)
    y[:n] *= np.linspace(0, 1, n)
    f0 = int(fade_from * SR)
    y[f0:] *= np.linspace(1.0, 0.0, len(y) - f0) ** 2
    return y


def loop(x: np.ndarray, start: float, end: float, fade: float) -> np.ndarray:
    a, b, f = int(start * SR), int(end * SR), int(fade * SR)
    body = x[a:b].copy()
    t = np.linspace(0.0, 1.0, f)
    body[:f] = body[:f] * np.sqrt(t) + body[-f:] * np.sqrt(1.0 - t)
    return body[:-f]


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    save(cut(load("molotov_break*.wav"), 0.45, 4.5, 2.2), "molotov_break.ogg", -1.0)
    save(cut(load("molotov_ignite*.wav"), 0.0, 2.6, 1.4), "molotov_ignite.ogg", -2.0)
    save(cut(load("molotov_throw*"), 0.12, 0.9, 0.35), "molotov_throw.ogg", -3.0)
    save(loop(load("fire_loop*.wav"), 0.2, 10.9, 1.0), "fire_loop.ogg", -3.0)


if __name__ == "__main__":
    main()
