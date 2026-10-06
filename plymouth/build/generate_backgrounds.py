#!/usr/bin/env python3
"""
Generates the theme's default backgrounds - original artwork, so the published theme
carries nothing whose licence it cannot pass on.

  theme/background-wide.png   3440x1440, used when the screen is wider than 2:1
  theme/background-16x9.png   1920x1080, used otherwise

Design: the Quantum Dark window colour (#202326) lifted slightly at the centre and
falling to near-black at the edges, so the firmware hand-off and Plymouth's own black
background meet it without a seam; and a soft glow behind the spinner, in the
spinner's own colour, so the two read as one thing.

Computed in floating point at full resolution and dithered once, just before the
8-bit conversion. An earlier version composited 8-bit Pillow masks scaled up from a
256-pixel gradient: that left hard rectangular edges where each mask ended and
concentric bands across the whole frame, which noise added afterwards only scattered.
Triangular dither before quantisation is what actually removes the bands.

To use your own art instead, see build/prepare_backgrounds.py and install.sh
--backgrounds.

Usage:
  python3 build/generate_backgrounds.py [--out-dir theme] [--glow R,G,B] [--seed N]

Needs numpy and Pillow. Deterministic for a given --seed on any platform: the noise
comes from numpy's PCG64, not the C library.
"""
import argparse
import os

import numpy as np
from PIL import Image

SIZES = {"background-wide.png": (3440, 1440), "background-16x9.png": (1920, 1080)}

EDGE = (9, 10, 12)         # near-black, to meet the firmware hand-off
BASE = (32, 35, 38)        # Quantum Dark [Colors:Window] BackgroundNormal, #202326
CENTRE = (40, 43, 48)      # a step lighter, so the middle has some depth
SPINNER_Y = 0.935          # must match SPINNER_Y in theme/quantum.script
GLOW_STRENGTH = 0.20


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def render(size, glow, seed):
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w / 2.0, h * 0.46

    # Elliptical distance from the centre, 0 there and 1 at the given radii. Every
    # weight below is a smooth function of a distance, so no layer has an edge.
    def dist(rx, ry, ox=cx, oy=cy):
        return np.sqrt(((x - ox) / rx) ** 2 + ((y - oy) / ry) ** 2)

    body = 1.0 - smoothstep(0.0, 1.0, dist(w * 0.70, h * 1.05))     # edge -> base
    core = 1.0 - smoothstep(0.0, 1.0, dist(w * 0.38, h * 0.62))     # base -> centre
    halo = np.exp(-0.5 * dist(h * 0.40, h * 0.16, w / 2.0, h * SPINNER_Y) ** 2)

    out = np.empty((h, w, 3), np.float32)
    for c in range(3):
        v = EDGE[c] + (BASE[c] - EDGE[c]) * body
        v = v + (CENTRE[c] - BASE[c]) * core
        v = v + (glow[c] - v) * (GLOW_STRENGTH * halo)
        out[..., c] = v

    # Triangular dither, one value per pixel shared by all channels so it reads as
    # luminance grain rather than colour speckle; +/-1 level at most.
    rng = np.random.Generator(np.random.PCG64(seed))
    d = (rng.random((h, w), np.float32) - rng.random((h, w), np.float32))[..., None]
    return Image.fromarray(np.clip(np.rint(out + d), 0, 255).astype(np.uint8), "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="theme")
    ap.add_argument("--glow", default="170,170,245",
                    help="R,G,B of the glow; the default is generate_wheel.py's tick colour")
    ap.add_argument("--seed", type=int, default=20261006)
    a = ap.parse_args()
    glow = tuple(int(c) for c in a.glow.split(","))
    os.makedirs(a.out_dir, exist_ok=True)
    for name, size in SIZES.items():
        out = os.path.join(a.out_dir, name)
        render(size, glow, a.seed).save(out, "PNG", optimize=True)
        print(f"{out} ({size[0]}x{size[1]}, {os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
