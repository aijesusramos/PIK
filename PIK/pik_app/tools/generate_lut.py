"""
PIK — Generador de LUTs 3D para los filtros analógicos.

Cada filtro se define como una función matemática  f(rgb) -> rgb  (sRGB, 0..1).
Este script la "hornea" en un cubo de N³ muestras y lo exporta en dos formatos:

  * <nombre>.cube  -> formato estándar (Resolve, Photoshop, ImageSharp, etc.).
                      Es la "fuente de verdad" y sirve para revisar el look
                      fuera de la app o portarlo al backend .NET.
  * <nombre>.png   -> "strip" 2D de (N*N) x N px que lee el shader de Flutter
                      (los fragment shaders de Flutter no tienen texturas 3D).
                      Columna = r + b*N, fila = g.

Uso:
    python3 generate_lut.py --out ../assets/luts --size 33
"""
import argparse
import os

import numpy as np
from PIL import Image

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float64)


# ---------------------------------------------------------------- utilidades
def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def s_curve(x, strength, pivot, amount):
    """Curva S sigmoide normalizada para que 0->0 y 1->1."""
    sig = lambda v: 1.0 / (1.0 + np.exp(-strength * (v - pivot)))
    s = (sig(x) - sig(0.0)) / (sig(1.0) - sig(0.0))
    return x + (s - x) * amount


def luma(rgb):
    return rgb @ LUMA


# ---------------------------------------------------------------- filtros
def look_original(rgb):
    """
    "Original": exposición baja, contraste alto, altas luces cálidas,
    medios tonos suaves, sombras verde/azul.
    Calibrado midiendo las fotos de referencia por bandas de luminancia
    (sombras verdosas con azul bajo, altas luces ámbar R>G>B).
    """
    # 1) Exposición: -0.4 EV en luz lineal (como subexponer la película)
    lin = srgb_to_linear(rgb) * 2.0 ** -0.4
    x = linear_to_srgb(lin)

    # 2) Contraste alto: curva S por canal (por canal = satura un poco, como el film)
    x = s_curve(x, strength=5.5, pivot=0.42, amount=0.85)

    # 3) Rango de película: negros ligeramente levantados, blancos que no clipean
    x = 0.022 + x * (0.965 - 0.022)

    L = luma(x)[..., None]

    # 4) Medios tonos suaves: baja saturación concentrada en los medios
    mid_w = np.exp(-(((L - 0.5) / 0.22) ** 2))
    sat = 0.93 - 0.13 * mid_w
    x = L + (x - L) * sat

    # 5) Sombras verde/azul (teal): se suma, para que tiña los negros
    sh_w = (1.0 - smoothstep(0.0, 0.5, L)) ** 1.5
    x = x + sh_w * np.array([-0.030, 0.022, 0.020])

    # 6) Altas luces cálidas: se multiplica, sólo afecta lo brillante
    hi_w = smoothstep(0.45, 1.0, L)
    x = x * (1.0 + hi_w * np.array([0.06, 0.005, -0.11]))

    return np.clip(x, 0.0, 1.0)


def hue_deg(rgb):
    """Tono en grados (0..360) y saturación tipo HSV de cada color."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    safe = np.where(d == 0, 1.0, d)
    h = np.where(mx == r, ((g - b) / safe) % 6,
        np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60.0
    h = np.where(d == 0, 0.0, h)
    s = np.where(mx == 0, 0.0, d / np.where(mx == 0, 1.0, mx))
    return h, s


def hue_band(h, center, width):
    """Peso 0..1 suave alrededor de un tono (distancia circular)."""
    dist = np.abs(((h - center + 180.0) % 360.0) - 180.0)
    return 1.0 - smoothstep(width * 0.5, width, dist)


def look_red_blue(rgb):
    """
    "Red&Blue": inspirado en Cinestill 800T (película tungsteno).
    Sombras azuladas, altas luces ligeramente hacia el rojo, amarillos/verdes
    desaturados, negros "lechosos". El neón rojo lo da la halation (preset),
    no el LUT.
    Calibrado con las referencias: sombras B>G>R, medios cian, el color casi
    todo concentrado en cian/azul (180-240°) y rojo (0-30°).
    """
    # 1) Balance tungsteno: la escena se enfría (en luz lineal)
    lin = srgb_to_linear(rgb) * np.array([0.90, 0.98, 1.10]) * 2.0 ** -0.1
    x = linear_to_srgb(lin)

    # 2) Contraste medio con negros levantados (look de alta sensibilidad)
    x = s_curve(np.clip(x, 0, 1), strength=5.0, pivot=0.40, amount=0.65)
    x = 0.04 + x * (0.97 - 0.04)

    # 3) Saturación selectiva: amarillos/verdes abajo, rojos un poco arriba
    h, _ = hue_deg(x)
    L = luma(x)[..., None]
    yellow_green = np.maximum(hue_band(h, 60, 45), hue_band(h, 115, 50))
    red = hue_band(h, 5, 35)
    sat = (1.0 - 0.60 * yellow_green + 0.12 * red)[..., None]
    x = L + (x - L) * sat
    # el verde que queda se corre hacia cian (típico del 800T)
    x = x + (hue_band(h, 120, 50)[..., None] * (x - L).clip(0) *
             np.array([0.0, -0.25, 0.25]))

    L = luma(x)[..., None]

    # 4) Sombras azules (con un toque de cian en los medios)
    sh_w = (1.0 - smoothstep(0.0, 0.55, L)) ** 1.3
    mid_w = np.exp(-(((L - 0.45) / 0.2) ** 2))
    x = x + sh_w * np.array([-0.025, 0.000, 0.050])
    x = x + mid_w * np.array([-0.015, 0.008, 0.015])

    # 5) Altas luces ligeramente hacia el rojo
    hi_w = smoothstep(0.55, 1.0, L)
    x = x * (1.0 + hi_w * np.array([0.045, -0.005, -0.06]))

    return np.clip(x, 0.0, 1.0)

def look_bw(rgb):
    """
    "B&W": inspirado en Kodak Tri-X 400.
    Altas luces cremosas (casi blancas, con hombro suave, sin cortarse),
    sombras profundas, piel en una gama amplia de grises claros y
    transiciones luz/sombra suaves; nada metálico.
    Calibrado con las referencias: totalmente neutras, negros ~0.04-0.08,
    altas luces hasta ~0.97.
    """
    # 1) Mezcla de canales en luz lineal. Un poco más de rojo que la
    #    luminancia estándar: la piel queda más clara y suave (pancromático).
    lin = srgb_to_linear(rgb)
    mono = lin @ np.array([0.30, 0.60, 0.10])
    x = linear_to_srgb(mono * 2.0 ** 0.1)

    # 2) Pie (toe): las sombras se hunden para dar profundidad
    toe = smoothstep(0.0, 0.45, x)
    x = x * (0.62 + 0.38 * toe) - (1 - toe) * 0.025

    # 3) Contraste moderado con pivote bajo: medios y piel con pendiente suave
    x = s_curve(np.clip(x, 0, 1), strength=4.2, pivot=0.36, amount=0.55)

    # 4) Hombro (shoulder): las altas luces se acercan a blanco sin cortarse
    shoulder_start = 0.70
    over = np.clip(x - shoulder_start, 0, None)
    room = 1.0 - shoulder_start
    x = np.where(x > shoulder_start,
                 shoulder_start + room * (1 - np.exp(-over / room * 1.15)) / (1 - np.exp(-1.15)),
                 x)

    # 5) Rango de película: negro profundo pero no puro, blanco "papel"
    x = 0.035 + np.clip(x, 0, 1) * (0.975 - 0.035)

    return np.repeat(x[..., None], 3, axis=-1)


FILTERS = {
    "original": look_original,
    "bw": look_bw,        
    "red_blue": look_red_blue,
}


# ---------------------------------------------------------------- exportación
def build_cube(fn, n):
    """Devuelve lut[b, g, r, 3] (orden .cube: r cambia más rápido)."""
    v = np.linspace(0.0, 1.0, n)
    b, g, r = np.meshgrid(v, v, v, indexing="ij")
    rgb = np.stack([r, g, b], axis=-1)
    return fn(rgb)


def write_cube(lut, path, title):
    n = lut.shape[0]
    with open(path, "w") as f:
        f.write(f'TITLE "{title}"\nLUT_3D_SIZE {n}\n')
        f.write("DOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n")
        for row in lut.reshape(-1, 3):
            f.write(f"{row[0]:.6f} {row[1]:.6f} {row[2]:.6f}\n")


def write_strip_png(lut, path):
    n = lut.shape[0]
    # lut[b, g, r] -> imagen[g, b*n + r]
    strip = lut.transpose(1, 0, 2, 3).reshape(n, n * n, 3)
    Image.fromarray(np.round(strip * 255).astype(np.uint8), "RGB").save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/luts")
    ap.add_argument("--size", type=int, default=33)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, fn in FILTERS.items():
        lut = build_cube(fn, args.size)
        write_cube(lut, os.path.join(args.out, f"{name}.cube"), f"PIK {name}")
        write_strip_png(lut, os.path.join(args.out, f"{name}.png"))
        print(f"{name}: {args.size}^3 -> .cube + .png")


if __name__ == "__main__":
    main()