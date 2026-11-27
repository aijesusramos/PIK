"""
PIK — Prototipo de escritorio del motor de revelado.

Replica, operación por operación, lo que hacen el shader `pik_develop.frag`
y `PikEngine` en Dart, para poder ajustar los presets en la compu sin
recompilar la app:

    python3 preview.py foto.jpg -o revelada.jpg [--filter red_blue] [--seed 7]

Filtros: original, red_blue, bw
Etapas:  LUT 3D (strip PNG)  ->  halation  ->  grano
"""
import argparse

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

# Deben coincidir con los FilmPreset de lib/engine/film_preset.dart
PRESET_ORIGINAL = dict(
    lut="../assets/luts/original.png",
    halation_weights=(0.2126, 0.7152, 0.0722),  # luminancia
    halation_threshold=0.72,
    halation_tint=(1.0, 0.32, 0.10),
    halation_strength=0.55,
    halation_radius=0.012,   # sigma como fracción del lado largo
    halation_scale=0.25,     # la halation se calcula a 1/4 de resolución
    grain_amount=0.045,
    grain_size=1 / 1500,     # tamaño de "cristal" como fracción del lado largo
)

PRESET_RED_BLUE = dict(
    lut="../assets/luts/red_blue.png",
    halation_weights=(0.9, 0.1, 0.0), # la halation nace en la capa roja: el neón rojo brilla
    halation_threshold=0.72,          # sólo las fuentes de luz "sangran"
    halation_tint=(1.0, 0.12, 0.06),  # rojo neón (800T no tiene capa remjet)
    halation_strength=3.0,            # pero sangran mucho
    halation_radius=0.022,            # resplandor más amplio
    halation_scale=0.25,
    grain_amount=0.04,                # ISO 800: más grano
    grain_size=1 / 1100,              # y más grueso
)

PRESET_BW = dict(
    lut="../assets/luts/bw.png",
    halation_weights=(0.2126, 0.7152, 0.0722),
    halation_threshold=0.82,          # sólo las luces más altas
    halation_tint=(1.0, 1.0, 1.0),    # neutro: en B&W es difusión, no color
    halation_strength=0.30,           # suave (Tri-X tiene capa antihalo)
    halation_radius=0.010,
    halation_scale=0.25,
    grain_amount=0.045,               # grano Tri-X visible pero fino
    grain_size=1 / 1300,
)

PRESETS = {"original": PRESET_ORIGINAL, "red_blue": PRESET_RED_BLUE, "bw": PRESET_BW}


# ---------------------------------------------------------------- etapa 1: LUT
def apply_lut_strip(img, strip):
    n = strip.shape[0]
    p = np.clip(img, 0, 1) * (n - 1)
    i0 = np.floor(p).astype(np.int32)
    i1 = np.minimum(i0 + 1, n - 1)
    f = p - i0

    def tex(r, g, b):  # == lutTexel() del shader
        return strip[g, b * n + r]

    r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
    r1, g1, b1 = i1[..., 0], i1[..., 1], i1[..., 2]
    fr, fg, fb = f[..., 0:1], f[..., 1:2], f[..., 2:3]
    c00 = tex(r0, g0, b0) * (1 - fr) + tex(r1, g0, b0) * fr
    c10 = tex(r0, g1, b0) * (1 - fr) + tex(r1, g1, b0) * fr
    c01 = tex(r0, g0, b1) * (1 - fr) + tex(r1, g0, b1) * fr
    c11 = tex(r0, g1, b1) * (1 - fr) + tex(r1, g1, b1) * fr
    c0 = c00 * (1 - fg) + c10 * fg
    c1 = c01 * (1 - fg) + c11 * fg
    return c0 * (1 - fb) + c1 * fb


# ---------------------------------------------------------------- etapa 2: halation
def halation_map(src_img, P):
    """== _buildHalation() en Dart:
    1) umbral + tinte a resolución completa (ColorFilter.matrix), así las luces
       delgadas (letras de neón) no se pierden;  2) reducir;  3) blur."""
    h, w = src_img.shape[:2]
    long_side = max(w, h)
    t = P["halation_threshold"]
    k = 1.0 / (1.0 - t)
    L = src_img @ np.array(P.get("halation_weights", LUMA), dtype=np.float32)
    mask = np.clip((L - t) * k, 0, 1)[..., None]
    tinted = mask * np.array(P["halation_tint"], dtype=np.float32)
    sw, sh = max(1, round(w * P["halation_scale"])), max(1, round(h * P["halation_scale"]))
    small = np.asarray(
        Image.fromarray((tinted * 255 + 0.5).astype(np.uint8)).resize((sw, sh), Image.BOX),
        dtype=np.float32) / 255
    sigma = P["halation_radius"] * long_side * P["halation_scale"]
    return np.stack([gaussian_filter(small[..., c], sigma, mode="nearest") for c in range(3)], -1)


def sample_bilinear(tex, out_h, out_w):
    """== halationAt() del shader (bilinear manual, uv del píxel de salida)."""
    th, tw = tex.shape[:2]
    ys = (np.arange(out_h) + 0.5) / out_h * th - 0.5
    xs = (np.arange(out_w) + 0.5) / out_w * tw - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, th - 1); y1 = np.clip(y0 + 1, 0, th - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, tw - 1); x1 = np.clip(x0 + 1, 0, tw - 1)
    fy = np.clip(ys - np.floor(ys), 0, 1)[:, None, None]
    fx = np.clip(xs - np.floor(xs), 0, 1)[None, :, None]
    a = tex[y0][:, x0] * (1 - fx) + tex[y0][:, x1] * fx
    b = tex[y1][:, x0] * (1 - fx) + tex[y1][:, x1] * fx
    return a * (1 - fy) + b * fy


# ---------------------------------------------------------------- etapa 3: grano
def hash12(px, py):
    """Hash de Dave Hoskins, igual que en el shader."""
    p3 = np.stack([px, py, px], -1) * 0.1031
    p3 = p3 - np.floor(p3)
    d = (p3 * (p3[..., [1, 2, 0]] + 33.33)).sum(-1, keepdims=True)
    p3 = p3 + d
    v = (p3[..., 0] + p3[..., 1]) * p3[..., 2]
    return v - np.floor(v)


def gauss(cx, cy, seed):
    u1 = np.maximum(hash12(cx + seed, cy + seed * 1.7), 1e-4)
    u2 = hash12(cx + seed + 17.13, cy - seed * 0.9 + 3.71)
    return np.sqrt(-2 * np.log(u1)) * np.cos(6.2831853 * u2)


def grain_noise(h, w, grain_px, seed):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    px, py = (xx + 0.5) / grain_px, (yy + 0.5) / grain_px
    ix, iy = np.floor(px), np.floor(py)
    fx, fy = px - ix, py - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = gauss(ix, iy, seed);     b = gauss(ix + 1, iy, seed)
    c = gauss(ix, iy + 1, seed); d = gauss(ix + 1, iy + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


# ---------------------------------------------------------------- pipeline
def develop(src, P, seed=7.0):
    h, w = src.shape[:2]
    strip = np.asarray(Image.open(P["lut"]).convert("RGB"), dtype=np.float32) / 255

    col = apply_lut_strip(src, strip)                                 # 1. color
    hal = sample_bilinear(halation_map(src, P), h, w)                 # 2. halation
    hal = np.clip(hal * P["halation_strength"], 0, 1)
    col = 1 - (1 - col) * (1 - hal)                                   #    (screen)
    L = (col @ LUMA)[..., None]                                       # 3. grano
    wgt = 0.35 + 0.65 * (4 * L * (1 - L))
    grain_px = max(1.0, P["grain_size"] * max(w, h))
    col = col + grain_noise(h, w, grain_px, seed)[..., None] * P["grain_amount"] * wgt
    return np.clip(col, 0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-o", "--out", default="revelada.jpg")
    ap.add_argument("--seed", type=float, default=7.0)
    ap.add_argument("--filter", default="original", choices=PRESETS.keys())
    a = ap.parse_args()
    src = np.asarray(Image.open(a.src).convert("RGB"), dtype=np.float32) / 255
    out = develop(src, PRESETS[a.filter], a.seed)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(a.out, quality=92)


if __name__ == "__main__":
    main()