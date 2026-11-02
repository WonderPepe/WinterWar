"""Cuts the T-26 turret sounds out of the downloaded recordings (not part of the game).
Run from the project folder:  python3 tools/make_turret_sounds.py   (needs ffmpeg + numpy)

  assets_source/336328__newagesoup__gear-spinning-loop.wav
      -> assets/audio/tank/turret_gear.ogg    gears turning, seamless loop (looped in tank.gd)
  assets_source/395041__aslakhostaker__turn-crank_squeak_old_metal_machine_loop.wav
      -> assets/audio/tank/turret_crank.ogg   the hand crank squeaking round, seamless loop
  assets_source/144824__zabuhailo__doorlatch.wav
      -> assets/audio/tank/turret_clunk_1..3.ogg  single metal latch clunks (random while turning / start)
      -> assets/audio/tank/turret_stop.ogg        the last part of the recording: the clunk when it stops
"""
import glob
import os
import subprocess

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets_source")
DST = os.path.join(ROOT, "assets", "audio", "tank")
SR = 44100


def find(pattern: str) -> str:
    hits = glob.glob(os.path.join(SRC, pattern))
    if not hits:
        raise SystemExit(f"missing assets_source/{pattern}")
    return hits[0]


def load(path: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def save(x: np.ndarray, name: str, peak_db: float) -> None:
    x = x / max(np.abs(x).max(), 1e-9) * 10 ** (peak_db / 20.0)
    path = os.path.join(DST, name)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f64le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", path], input=x.astype(np.float64).tobytes(), check=True)
    print(f"{name}: {len(x) / SR:.2f} s, {os.path.getsize(path) / 1000:.0f} kB")


def loop(x: np.ndarray, start: float, end: float, fade: float) -> np.ndarray:
    """Cuts start..end and blends the last `fade` seconds into the beginning: no click at the seam."""
    a, b, f = int(start * SR), int(end * SR), int(fade * SR)
    body = x[a:b].copy()
    head = body[:f].copy()
    tail = body[-f:]
    t = np.linspace(0.0, 1.0, f)
    body[:f] = head * np.sqrt(t) + tail * np.sqrt(1.0 - t)
    return body[:-f]


def hit(x: np.ndarray, start: float, length: float, fade_from: float) -> np.ndarray:
    """One struck sound: tiny fade-in, then a fade-out from `fade_from` seconds on."""
    a = int(start * SR)
    y = x[a:a + int(length * SR)].copy()
    n = int(0.003 * SR)
    y[:n] *= np.linspace(0, 1, n)
    f0 = int(fade_from * SR)
    y[f0:] *= np.exp(-np.linspace(0.0, 6.0, len(y) - f0))
    return y


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    save(loop(load(find("336328__*.wav")), 0.0, 12.2, 0.6), "turret_gear.ogg", -3.0)
    save(loop(load(find("395041__*.wav")), 0.0, 7.4, 0.5), "turret_crank.ogg", -3.0)
    latch = load(find("144824__*.wav"))
    for i, t in enumerate([2.58, 17.01, 20.16], 1):  # three different clunks
        save(hit(latch, t, 0.7, 0.15), f"turret_clunk_{i}.ogg", -3.0)
    save(hit(latch, 30.57, 1.3, 0.55), "turret_stop.ogg", -1.0)  # the end of the recording


if __name__ == "__main__":
    main()
