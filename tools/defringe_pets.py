#!/usr/bin/env python3
"""Чистка краёв вырезанных картинок питомцев (Companion-*.imageset).

Что исправляет:
  1. Тёмная кайма: у полупрозрачных пикселей по контуру цвет «заражён» фоном вырезки.
     Цвет восстанавливается из ближайшего тела персонажа (нормализованная свёртка).
  2. Рваный контур: широкая (5 px) ступенчатая альфа подтягивается S-кривой и слегка
     сглаживается — край становится чистым и без «лесенки».
  3. Срезанный низ (пингвин, робот, овечка, ленивец): последние пиксели плавно уходят
     в прозрачность, чтобы не было жёсткой горизонтальной линии.

Светящиеся персонажи (капля, огонёк, росток) имеют намеренный мягкий ореол — их не трогаем.

Запуск: python3 tools/defringe_pets.py   (нужны numpy, scipy, Pillow). Скрипт идемпотентен.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                    "HabitFlow", "Resources", "Assets.xcassets")
GLOW = {"drop", "flame", "sprout"}
ALPHA_LO, ALPHA_HI = 0.22, 0.92   # S-кривая: ниже LO — прозрачно, выше HI — полностью плотно
COLOR_SIGMA = 2.5                  # радиус усреднения цвета тела
EDGE_SIGMA = 0.55                  # лёгкое сглаживание альфы
BOTTOM_FADE = 12                   # px плавного ухода в прозрачность у обрезанного низа
RIM_BAND = 6                       # ширина полосы у края, где ищем тёмный ободок
RIM_MARGIN, RIM_SOFT = 22.0, 35.0  # насколько темнее тела (яркость 0…255) считается ободком


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def clean(path, name):
    img = Image.open(path).convert("RGBA")
    arr = np.asarray(img).astype(np.float64)
    rgb, a = arr[..., :3], arr[..., 3] / 255.0
    h, w = a.shape

    # 1. Цвет каймы берём у тела
    solid = (a >= 0.98).astype(np.float64)
    weight = ndi.gaussian_filter(solid, COLOR_SIGMA)
    body = np.stack([ndi.gaussian_filter(rgb[..., c] * solid, COLOR_SIGMA) for c in range(3)], axis=-1)
    body = body / np.maximum(weight, 1e-6)[..., None]
    # где тела рядом почти нет — берём цвет ближайшего плотного пикселя
    idx = ndi.distance_transform_edt(solid == 0, return_distances=False, return_indices=True)
    nearest = rgb[idx[0], idx[1]]
    use_body = (weight > 0.03)[..., None]
    fixed = np.where(use_body, body, nearest)
    edge = (a < 0.98)[..., None]
    rgb2 = np.where(edge, fixed, rgb)

    # 1b. Тёмный непрозрачный ободок у края (остатки фона): пиксели в полосе RIM_BAND px от края,
    # заметно темнее тела, заменяются цветом тела. Светлые подсветки и контуры светлее тела остаются.
    inside = a >= 0.5
    depth = ndi.distance_transform_edt(inside)
    core = (depth > RIM_BAND).astype(np.float64)
    core_w = ndi.gaussian_filter(core, 3.0)
    core_rgb = np.stack([ndi.gaussian_filter(rgb[..., c] * core, 3.0) for c in range(3)], axis=-1)
    core_rgb = core_rgb / np.maximum(core_w, 1e-6)[..., None]
    lum = lambda x: 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]
    gap = lum(core_rgb) - lum(rgb2)
    f = smoothstep((gap - RIM_MARGIN) / RIM_SOFT)
    f = np.where((depth <= RIM_BAND) & (a >= 0.98) & (core_w > 0.03), f, 0.0)[..., None]
    rgb2 = rgb2 * (1 - f) + core_rgb * f

    # 2. Альфа: S-кривая + лёгкое сглаживание
    a2 = smoothstep((a - ALPHA_LO) / (ALPHA_HI - ALPHA_LO))
    a2 = ndi.gaussian_filter(a2, EDGE_SIGMA)
    a2 = np.where(a >= 0.98, 1.0, a2)  # внутри остаётся 1

    # 3. Срезанный низ
    if (a[-1, :] > 0.03).sum() > 3:
        fade = np.ones(h)
        for i in range(BOTTOM_FADE):
            fade[h - 1 - i] = smoothstep(i / BOTTOM_FADE)
        a2 = a2 * fade[:, None]

    out = np.dstack([np.clip(rgb2, 0, 255), np.clip(a2 * 255.0, 0, 255)]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    print(f"  {name}: готово ({w}×{h})")


def main():
    paths = sorted(glob.glob(os.path.join(ROOT, "Companion-*.imageset", "*.png")))
    if not paths:
        sys.exit("Не нашёл картинки питомцев")
    for p in paths:
        name = os.path.splitext(os.path.basename(p))[0]
        if name in GLOW:
            print(f"  {name}: пропуск (светящийся)")
            continue
        clean(p, name)


if __name__ == "__main__":
    main()
