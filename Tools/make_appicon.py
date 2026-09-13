#!/usr/bin/env python3
"""Erzeugt das App-Icon (1024x1024 PNG) ohne externe Abhaengigkeiten.

Unter Linux ist weder Xcode noch Pillow noetig -- das PNG wird hier direkt
aus Pixeldaten mit zlib/struct geschrieben.

    python3 Tools/make_appicon.py

Ergebnis: Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""
from __future__ import annotations

import math
import os
import struct
import zlib

SIZE = 1024
SS = 2  # 2x Supersampling fuer weiche Kanten
W = SIZE * SS

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png",
)

TEAL = (79, 201, 254)
MINT = (79, 254, 201)
INK_TOP = (12, 26, 33)
INK_BOTTOM = (5, 10, 14)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ring(px, py, cx, cy, r, thickness, a0=0.0, a1=math.tau):
    """True, wenn (px,py) im Kreisring mit Winkelausschnitt [a0,a1] liegt."""
    dx, dy = px - cx, py - cy
    d = math.hypot(dx, dy)
    if abs(d - r) > thickness / 2:
        return False
    ang = math.atan2(dy, dx) % math.tau
    return a0 <= ang <= a1


def rounded_box(px, py, cx, cy, hw, hh, radius):
    dx = abs(px - cx) - (hw - radius)
    dy = abs(py - cy) - (hh - radius)
    dx = max(dx, 0.0)
    dy = max(dy, 0.0)
    return math.hypot(dx, dy) <= radius and abs(px - cx) <= hw and abs(py - cy) <= hh


def segment(px, py, x0, y0, x1, y1, thickness):
    vx, vy = x1 - x0, y1 - y0
    wx, wy = px - x0, py - y0
    ll = vx * vx + vy * vy
    t = 0.0 if ll == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / ll))
    return math.hypot(wx - vx * t, wy - vy * t) <= thickness / 2


def render() -> bytearray:
    rows = bytearray()
    cx = W / 2

    # Geometrie (in Supersampling-Koordinaten)
    band_cy = 0.56 * W
    band_r = 0.30 * W
    band_th = 0.055 * W
    cup_hw = 0.062 * W
    cup_hh = 0.115 * W
    cup_cy = band_cy + 0.105 * W
    clock_r = 0.155 * W
    clock_cy = band_cy + 0.02 * W

    for y in range(W):
        row = bytearray()
        for x in range(W):
            t = y / (W - 1)
            r, g, b = lerp(INK_TOP, INK_BOTTOM, t)

            # weicher Lichtschein hinter dem Kopfhoerer
            glow = max(0.0, 1.0 - math.hypot(x - cx, y - band_cy) / (0.52 * W))
            glow = glow ** 3 * 0.30
            r = min(255, round(r + TEAL[0] * glow))
            g = min(255, round(g + TEAL[1] * glow))
            b = min(255, round(b + TEAL[2] * glow))

            # Kopfhoerer-Buegel (oberer Halbkreis)
            on_band = ring(x, y, cx, band_cy, band_r, band_th, math.pi, math.tau)
            # Ohrmuscheln links/rechts
            on_cup = (rounded_box(x, y, cx - band_r, cup_cy, cup_hw, cup_hh, cup_hw)
                      or rounded_box(x, y, cx + band_r, cup_cy, cup_hw, cup_hh, cup_hw))

            if on_band or on_cup:
                shade = 0.55 + 0.45 * (1.0 - y / W)
                col = lerp(TEAL, MINT, min(1.0, max(0.0, (x / W))))
                r, g, b = [min(255, round(c * shade + 40)) for c in col]

            # Ziffernblatt
            d_clock = math.hypot(x - cx, y - clock_cy)
            if d_clock <= clock_r:
                r, g, b = 9, 18, 24
                if d_clock >= clock_r - 0.011 * W:
                    r, g, b = MINT
                # Zeiger: kurz auf 12, lang auf 4
                if segment(x, y, cx, clock_cy, cx, clock_cy - clock_r * 0.62, 0.017 * W):
                    r, g, b = 255, 255, 255
                if segment(x, y, cx, clock_cy,
                           cx + clock_r * 0.55, clock_cy + clock_r * 0.42, 0.017 * W):
                    r, g, b = 255, 255, 255

            row += bytes((r, g, b))
        rows.append(0)  # PNG-Filter "None"
        rows += row
    return rows


def downsample(src: bytearray) -> bytearray:
    """Mittelt SSxSS Pixel zu einem Zielpixel (Anti-Aliasing)."""
    stride = W * 3 + 1
    out = bytearray()
    for y in range(SIZE):
        out.append(0)
        for x in range(SIZE):
            acc = [0, 0, 0]
            for dy in range(SS):
                base = (y * SS + dy) * stride + 1 + (x * SS) * 3
                for dx in range(SS):
                    off = base + dx * 3
                    acc[0] += src[off]
                    acc[1] += src[off + 1]
                    acc[2] += src[off + 2]
            n = SS * SS
            out += bytes((acc[0] // n, acc[1] // n, acc[2] // n))
    return out


def chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def main() -> None:
    raw = downsample(render())
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(OUT, "wb") as fh:
        fh.write(png)
    print(f"geschrieben: {OUT} ({len(png)} Bytes)")


if __name__ == "__main__":
    main()
