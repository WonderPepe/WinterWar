# Synthesizes simple placeholder weapon sounds (no external assets).
import numpy as np, wave, sys
SR = 22050
rng = np.random.default_rng(1939)
out = sys.argv[1]

def lowpass(x, a):  # one-pole low-pass, a in (0,1): smaller = darker
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc); y[i] = acc
    return y

def env(n, attack, decay):
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = int(attack * SR)
    if a > 0: e[:a] *= np.linspace(0, 1, a)
    return e

def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    data = (x * 32767).astype(np.int16)
    with wave.open(f"{out}/{name}", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

def click(n_total, at, freq, length=0.02, amp=1.0):
    x = np.zeros(n_total); n = int(length * SR); s = int(at * SR)
    t = np.arange(n) / SR
    c = (rng.uniform(-1, 1, n) * 0.6 + np.sin(2*np.pi*freq*t)) * np.exp(-t / (length/4))
    x[s:s+n] += c[:max(0, min(n, n_total - s))] * amp
    return x

def gunshot(dur, crack_decay, boom_decay, boom_hz, tail_decay, bright):
    n = int(dur * SR); t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    crack = noise * env(n, 0.0005, crack_decay)
    body = lowpass(noise, bright) * env(n, 0.001, tail_decay) * 3.0
    boom = np.sin(2*np.pi*boom_hz*t * (1 - 0.3*t/dur)) * env(n, 0.002, boom_decay) * 0.8
    return crack + body + boom

save("mosin_shot.wav", gunshot(1.3, 0.012, 0.12, 55, 0.35, 0.25))
save("suomi_shot.wav", gunshot(0.35, 0.006, 0.05, 80, 0.07, 0.35))
n = int(0.6 * SR)
save("bolt_cycle.wav", click(n, 0.0, 2400, 0.03) + click(n, 0.12, 1700, 0.05, 0.7) + click(n, 0.33, 2000, 0.05, 0.8) + click(n, 0.45, 2600, 0.03))
n = int(1.2 * SR)
save("reload.wav", click(n, 0.05, 1500, 0.06) + click(n, 0.3, 1100, 0.08, 0.8) + click(n, 0.75, 1900, 0.05) + click(n, 0.95, 2500, 0.03, 0.9))
n = int(0.15 * SR)
save("empty_click.wav", click(n, 0.0, 3000, 0.02))
print("sounds written")
