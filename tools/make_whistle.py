# G2: synthesizes the placeholder officer's whistle (a "pea" whistle: a high tone that
# warbles as the little ball inside rattles). Two blasts: short – long.
# A real recording in assets/audio/recorded/officer_whistle… replaces it automatically.
#   python3 tools/make_whistle.py assets/audio
import numpy as np, wave, sys
SR = 44100
rng = np.random.default_rng(1940)
out = sys.argv[1]

def blast(dur, base_hz):
    n = int(dur * SR); t = np.arange(n) / SR
    rattle = 32.0 + 4.0 * np.sin(2 * np.pi * 1.3 * t)          # pea rattle rate (Hz)
    phase_r = 2 * np.pi * np.cumsum(rattle) / SR
    freq = base_hz * (1.0 + 0.035 * np.sin(phase_r)) * (1.0 + 0.02 * np.minimum(t / 0.05, 1.0))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    am = 0.75 + 0.25 * np.sin(phase_r)
    breath = rng.uniform(-1, 1, n)
    acc = 0.0; hp = np.zeros(n)                               # crude high-pass breath noise
    for i, v in enumerate(breath):
        acc += 0.15 * (v - acc); hp[i] = v - acc
    e = np.ones(n)
    a = int(0.015 * SR); r = int(0.06 * SR)
    e[:a] = np.linspace(0, 1, a); e[-r:] = np.linspace(1, 0, r)
    return (tone * am + hp * 0.12) * e

gap = np.zeros(int(0.09 * SR))
x = np.concatenate([blast(0.22, 2850.0), gap, blast(0.75, 2800.0), np.zeros(int(0.2 * SR))])
x = x / (np.max(np.abs(x)) + 1e-9) * 0.8
with wave.open(f"{out}/officer_whistle_placeholder.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
print("officer_whistle_placeholder.wav written")
