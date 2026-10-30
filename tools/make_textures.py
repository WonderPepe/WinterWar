"""Generates the procedural textures in assets/textures/ (not part of the game).

All textures tile seamlessly (noise is made with an FFT, which is periodic by nature).
Run from the project folder:  python3 tools/make_textures.py
Needs numpy and Pillow.
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
rng = np.random.default_rng(1939)


def fft_noise(h, w, falloff=2.0, low=1.0, high=None, stretch=(1.0, 1.0)):
    """Tileable noise with a 1/f^falloff spectrum. stretch=(sx, sy) makes it anisotropic."""
    white = rng.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None] * h * stretch[1]
    fx = np.fft.fftfreq(w)[None, :] * w * stretch[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / np.power(f, falloff)
    amp[f < low] = 0.0
    if high is not None:
        amp *= np.exp(-(f / high) ** 2)
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    out -= out.min()
    out /= max(out.max(), 1e-6)
    return out


def height_to_normal(height, strength):
    """Tileable normal map (OpenGL style, green = up) from a height map."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save(arr, name, mode="RGB"):
    img = Image.fromarray(np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8), mode)
    img.save(os.path.join(OUT, name), optimize=True)
    print("saved", name, img.size)


def snow():
    n = 512
    # Wind ripples (sastrugi): long in x, short in y, plus a fine grain.
    ripples = fft_noise(n, n, falloff=1.6, low=4, high=60, stretch=(4.0, 1.0))
    grain = fft_noise(n, n, falloff=0.6, low=40, high=200)
    height = ripples * 1.0 + grain * 0.15
    save(height_to_normal(height, 6.0), "snow_normal.png")
    # Mask: R = large soft variation, G = sparkle points, B = fine grain
    macro = fft_noise(n, n, falloff=2.2, low=1, high=12)
    sparkle = np.zeros((n, n))
    count = 2600
    ys = rng.integers(0, n, count)
    xs = rng.integers(0, n, count)
    sparkle[ys, xs] = rng.uniform(0.5, 1.0, count)
    # Soften each point a little (tileable 3x3 blur keeps the max in the centre).
    soft = sparkle.copy()
    for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        soft = np.maximum(soft, np.roll(np.roll(sparkle, dy, 0), dx, 1) * 0.35)
    save(np.dstack([macro, soft, grain]), "snow_mask.png")


def logs():
    """2 m x 1 m wall of horizontal logs (5 logs, ~20 cm each). Texture 1024 x 512."""
    w, h = 1024, 512
    logs_per_tile = 5
    lh = h // logs_per_tile + 1
    v = np.arange(h)[:, None].repeat(w, 1).astype(float)
    u = np.arange(w)[None, :].repeat(h, 0).astype(float)
    albedo = np.zeros((h, w, 3))
    height = np.zeros((h, w))
    bark_streaks = fft_noise(h, w, falloff=1.2, low=3, high=120, stretch=(14.0, 1.0))
    knots = fft_noise(h, w, falloff=2.0, low=6, high=40)
    fine = fft_noise(h, w, falloff=0.8, low=30, high=250)
    log_index = np.minimum((v / (h / logs_per_tile)).astype(int), logs_per_tile - 1)
    local = (v - log_index * (h / logs_per_tile)) / (h / logs_per_tile)  # 0..1 inside a log
    across = local * 2.0 - 1.0  # -1..1, 0 = log centre
    radius_profile = np.sqrt(np.clip(1.0 - across ** 2 * 0.92, 0.0, 1.0))
    # Each log: own tint, own joint position (where two logs meet end to end).
    tints = [np.array(c) for c in [(0.33, 0.25, 0.18), (0.29, 0.22, 0.16), (0.38, 0.3, 0.21),
                                   (0.31, 0.24, 0.19), (0.42, 0.34, 0.24)]]
    joint_u = rng.integers(80, w - 80, logs_per_tile)
    for i in range(logs_per_tile):
        m = log_index == i
        base = tints[i]
        debarked = i in (2, 4)  # a few lighter, debarked poles
        streak = bark_streaks if not debarked else fine
        col = base[None, None, :] * (0.75 + 0.5 * streak[..., None])
        if debarked:
            col = col * 1.25 + 0.04
        albedo[m] = col[m]
        joint = np.abs(u - joint_u[i])
        cut = np.clip(1.0 - joint / 3.0, 0.0, 1.0)  # dark seam at the joint
        albedo[m] *= (1.0 - cut[m, None] * 0.7)
        height[m] = (radius_profile * (0.85 + 0.15 * streak) - cut * 0.3)[m]
    # Dark gaps between logs (earth / shadow) and some knots.
    gap = np.clip(1.0 - radius_profile * 1.8, 0.0, 1.0)
    albedo *= (1.0 - gap[..., None] * 0.85)
    albedo *= (0.6 + 0.4 * radius_profile[..., None])  # rounder look: darker towards the log edges
    albedo *= (0.9 + 0.2 * knots[..., None])
    albedo *= (0.92 + 0.16 * fine[..., None])
    save(np.clip(albedo, 0, 1), "logs_albedo.png")
    save(height_to_normal(height + fine * 0.04, 14.0), "logs_normal.png")


def bark():
    """Spruce bark for tree trunks: grey-brown flaky plates, vertical. 256 x 512."""
    w, h = 256, 512
    plates = fft_noise(h, w, falloff=1.4, low=3, high=50, stretch=(1.0, 5.0))
    fine = fft_noise(h, w, falloff=0.8, low=20, high=200)
    cracks = np.clip((plates - 0.38) * 6.0, 0.0, 1.0)
    base = np.array([0.30, 0.24, 0.19])
    grey = np.array([0.42, 0.40, 0.37])
    col = base[None, None, :] * (1 - plates[..., None] * 0.6) + grey[None, None, :] * plates[..., None] * 0.6
    col *= (0.35 + 0.65 * cracks[..., None])
    col *= (0.85 + 0.3 * fine[..., None])
    save(np.clip(col, 0, 1), "bark.png")


def treeline():
    """Distant forest silhouette, tileable left-right. RGBA 2048 x 256 (bottom = ground)."""
    w, h = 2048, 256
    alpha = np.zeros((h, w))
    snow = np.zeros((h, w))
    shade = np.zeros((h, w))
    ys = np.arange(h)[:, None].astype(float)
    xs = np.arange(w)[None, :].astype(float)
    # Background row (smaller trees) then foreground row (taller).
    for row, (count, hmin, hmax) in enumerate([(260, 70, 140), (200, 110, 215)]):
        for _ in range(count):
            cx = rng.uniform(0, w)
            th = rng.uniform(hmin, hmax)
            tw = th * rng.uniform(0.22, 0.32)
            top = h - th
            dx = np.abs(((xs - cx + w / 2) % w) - w / 2)  # wraps around: tileable
            t = np.clip((ys - top) / th, 0.0, 1.0)  # 0 at the tip, 1 at the ground
            # Jagged branch tiers.
            tier = 0.82 + 0.18 * np.abs(np.sin(t * th / 9.0 * np.pi))
            inside = (dx < tw * t * tier) & (ys >= top)
            alpha = np.where(inside, 1.0, alpha)
            shade = np.where(inside, 0.75 + 0.25 * row + rng.uniform(-0.08, 0.08), shade)
            snow_here = inside & (np.sin(t * th / 9.0 * np.pi) > 0.55) & (rng.random((h, w)) < 0.5)
            snow = np.where(inside, np.where(snow_here, 1.0, 0.0), snow)
    green = np.array([0.07, 0.12, 0.09])
    white = np.array([0.82, 0.86, 0.92])
    col = green[None, None, :] * shade[..., None]
    col = col * (1 - snow[..., None] * 0.6) + white[None, None, :] * snow[..., None] * 0.6
    rgba = np.dstack([col, alpha])
    save(rgba, "treeline.png", "RGBA")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    snow()
    logs()
    bark()
    treeline()
