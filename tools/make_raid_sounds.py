"""Placeholder sounds for the air raid (A1). Real recordings replace them: put files named
raid_whistle*.ogg / raid_boom*.ogg / raid_engine*.ogg in assets/audio/recorded/.
  python3 tools/make_raid_sounds.py
Own random generator; does not touch the other sound scripts."""
import wave
import numpy as np

SR = 32000
rng = np.random.default_rng(1939)
OUT = "assets/audio/air_raid/"


def write(name, x):
    x = x / max(np.max(np.abs(x)), 1e-9) * 0.9
    with wave.open(OUT + name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def lowpass(x, hz):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1.0 / (1.0 + (freqs / hz) ** 4)
    return np.fft.irfft(f, len(x))


def bandpass(x, lo, hi):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= ((freqs > lo) & (freqs < hi)).astype(float)
    return np.fft.irfft(f, len(x))


# A falling bomb: a thin scream whose pitch drops, louder and louder, ending at the impact.
n = int(2.6 * SR)
t = np.arange(n) / SR
prog = t / t[-1]
freq = 3200 - 1900 * prog ** 0.8 + 40 * np.sin(2 * np.pi * 7 * t)
phase = 2 * np.pi * np.cumsum(freq) / SR
tone = np.sin(phase) + 0.45 * np.sin(2 * phase) + 0.2 * np.sin(3 * phase)
air = bandpass(rng.standard_normal(n), 1500, 5500)
env = (prog ** 1.6) * (1 - np.exp(-t * 6))
x = (tone * 0.6 + air * 1.4) * env
x[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
write("raid_whistle_placeholder.wav", x)

# A big bomb: crack, deep thump that sinks in pitch, long rumble.
n = int(4.0 * SR)
t = np.arange(n) / SR
thump_f = 28 + 60 * np.exp(-t / 0.18)
thump = np.sin(2 * np.pi * np.cumsum(thump_f) / SR) * np.exp(-t / 0.55)
crack = lowpass(rng.standard_normal(n), 3500) * np.exp(-t / 0.05)
rumble = lowpass(rng.standard_normal(n), 140) * np.exp(-t / 1.1) * (1 - np.exp(-t * 25))
mid = bandpass(rng.standard_normal(n), 150, 900) * np.exp(-t / 0.35)
x = 1.0 * thump + 0.7 * crack + 2.2 * rumble + 0.5 * mid
x[-int(0.3 * SR):] *= np.linspace(1, 0, int(0.3 * SR))
write("raid_boom_placeholder.wav", x)
print("done")
