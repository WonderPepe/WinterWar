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
# (bolt_cycle.wav removed: the owner didn't want it – a real recording goes in
# assets/audio/recorded/bolt_mosin…. Still generated, not saved, to keep the random numbers the same.)
_ = click(n, 0.0, 2400, 0.03) + click(n, 0.12, 1700, 0.05, 0.7) + click(n, 0.33, 2000, 0.05, 0.8) + click(n, 0.45, 2600, 0.03)
n = int(1.2 * SR)
# (reload.wav removed: sounded bad – real recordings go in assets/audio/recorded/. The call
#  stays so the random numbers below come out the same.)
_ = (click(n, 0.05, 1500, 0.06) + click(n, 0.3, 1100, 0.08, 0.8) + click(n, 0.75, 1900, 0.05) + click(n, 0.95, 2500, 0.03, 0.9))
n = int(0.15 * SR)
save("empty_click.wav", click(n, 0.0, 3000, 0.02))
n = int(0.08 * SR)
t = np.arange(n) / SR
# (hit_tick.wav removed: the owner didn't want a hit sound. Still generated, not saved,
#  to keep the random numbers the same.)
_ = (np.sin(2*np.pi*1800*t) * np.exp(-t / 0.015) + click(n, 0.0, 3200, 0.01, 0.3))
# Maxim (added in W1): heavy rifle cartridge, short tail so fast fire doesn't turn to mush.
save("maxim_shot.wav", gunshot(0.45, 0.009, 0.07, 48, 0.12, 0.28))
n = int(2.0 * SR)
_ = (click(n, 0.05, 900, 0.08) + click(n, 0.45, 1300, 0.06, 0.8) + click(n, 0.8, 700, 0.12, 0.9)
     + click(n, 1.3, 1800, 0.05) + click(n, 1.55, 1100, 0.07, 0.9) + click(n, 1.8, 2300, 0.04))
# ---- P2: footsteps, ambience, bullet cracks ----
def bandnoise(n, lo_a, hi_a):
    """Noise between two one-pole filters (a crude band-pass)."""
    x = rng.uniform(-1, 1, n)
    return lowpass(x, hi_a) - lowpass(lowpass(x, hi_a), lo_a)

def crunch(dur, grains, bright, decay):
    """Snow crunch: many tiny crackles in a short, fast-decaying burst."""
    n = int(dur * SR); x = np.zeros(n)
    for _ in range(grains):
        at = int(abs(rng.normal(0.02, 0.025)) * SR)
        ln = int(rng.uniform(0.002, 0.008) * SR)
        if at + ln >= n: continue
        g = rng.uniform(-1, 1, ln) * np.exp(-np.arange(ln) / (ln / 3)) * rng.uniform(0.3, 1.0)
        x[at:at+ln] += g
    x = lowpass(x, bright) + 0.25 * lowpass(rng.uniform(-1, 1, n), 0.05) * env(n, 0.005, decay)
    return x * env(n, 0.002, decay)

# (Generated footsteps were removed in P2: they sounded bad. Real recordings go in
#  assets/audio/footsteps/ – see scripts/game/footstep_sounds.gd. The crunch() helper is
#  kept: the random numbers below must stay in the same order to give the same sounds.)
for i in range(3):
    crunch(0.22, 160, 0.55, 0.07)
for i in range(2):
    crunch(0.18, 60, 0.25, 0.05)
for i in range(2):
    rng.uniform(-1, 1, int(0.2 * SR))

# Wind: 12 s seamless loop (noise filtered, slowly swelling gusts). The end is cross-faded into
# the start so it can loop without a click.
n = int(12 * SR); fade = int(1.0 * SR)
raw = rng.uniform(-1, 1, n + fade)
low = lowpass(raw, 0.02) * 2.5 + lowpass(raw, 0.08) * 0.6
t = np.arange(n + fade) / SR
gust = 0.6 + 0.25 * np.sin(2*np.pi*t/12*1) + 0.15 * np.sin(2*np.pi*t/12*3 + 1.0)
w = low * gust
loop = w[:n].copy()
ramp = np.linspace(0, 1, fade)
loop[:fade] = loop[:fade] * ramp + w[n:n+fade] * (1 - ramp)
save("wind_loop.wav", loop)

# Distant artillery: deep thump and a long rolling rumble.
for i, (hz, dur) in enumerate([(32, 4.5), (26, 5.5)]):
    n = int(dur * SR); t = np.arange(n) / SR
    boom = np.sin(2*np.pi*hz*t*(1 - 0.2*t/dur)) * env(n, 0.03, 0.5)
    rumble = lowpass(lowpass(rng.uniform(-1, 1, n), 0.01), 0.02) * env(n, 0.15, 1.6) * 6.0
    save(f"artillery_far_{i+1}.wav", boom + rumble)

# Distant machine-gun bursts: dull pops in a rhythm.
for i, shots in enumerate([9, 15]):
    rate = 0.1 + 0.01 * i
    dur = shots * rate + 1.5
    n = int(dur * SR); x = np.zeros(n)
    for k in range(shots):
        at = max(0, int((k * rate + rng.uniform(-0.005, 0.005)) * SR))
        m = int(0.25 * SR)
        pop = lowpass(rng.uniform(-1, 1, m), 0.06) * env(m, 0.001, 0.05) * rng.uniform(0.7, 1.0)
        x[at:at+m] += pop[:max(0, min(m, n - at))]
    x += lowpass(rng.uniform(-1, 1, n), 0.01) * env(n, 0.2, 0.8) * 0.8 # echo tail
    save(f"mg_far_{i+1}.wav", x)

# Bullet passing close by: a sharp supersonic crack with a short whizz.
for i in range(2):
    n = int(0.25 * SR); t = np.arange(n) / SR
    crack = rng.uniform(-1, 1, n) * env(n, 0.0002, 0.004) * 1.5
    zip_ = bandnoise(n, 0.2, 0.7) * env(n, 0.001, 0.03) * 0.8
    save(f"bullet_crack_{i+1}.wav", crack + zip_)

# Being hit: (hurt_thump.wav removed – sounded bad; real recordings: assets/audio/recorded/hurt…)
n = int(0.35 * SR); t = np.arange(n) / SR
_ = (np.sin(2*np.pi*70*t*(1 - 0.4*t)) * env(n, 0.002, 0.08) + lowpass(rng.uniform(-1, 1, n), 0.15) * env(n, 0.001, 0.03) * 0.7)

# ---- W2: steam hissing from the Maxim's water jacket: 3 s seamless loop ----
n = int(3 * SR); fade = int(0.5 * SR)
raw = bandnoise(n + fade, 0.25, 0.85)
t = np.arange(n + fade) / SR
w = raw * (0.8 + 0.2 * np.sin(2*np.pi*t/3*2)) # it "breathes" a little
loop = w[:n].copy()
ramp = np.linspace(0, 1, fade)
loop[:fade] = loop[:fade] * ramp + w[n:n+fade] * (1 - ramp)
save("steam_hiss.wav", loop * 0.6)

print("sounds written")
