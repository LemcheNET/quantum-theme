#!/usr/bin/env python3
"""
Generates the single-frame spinner asset (theme/wheel.png) for the
Quantum Plymouth theme. The theme rotates this one frame every
refresh tick with Image.Rotate(), so no frame sequence is needed.

Layout: N ticks around a ring. Tick 0 (12 o'clock) is the brightest "head";
brightness falls off counter-clockwise, so when the image rotates clockwise
the head leads and the tail trails. If the preview shows the tail leading,
flip the sign of SPIN_SPEED in quantum.script -- don't regenerate.

Usage:
  python3 build/generate_wheel.py theme/wheel.png [--size 240] [--ticks 12] [--color R,G,B]

Status: run 2026-09-24 in the Cowork VM (Pillow); output checked visually.
"""
import argparse
import math
from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output")
    ap.add_argument("--size", type=int, default=240, help="final PNG size (square)")
    ap.add_argument("--ticks", type=int, default=12, help="number of ticks")
    ap.add_argument("--color", default="170,170,245",
                    help="R,G,B of the ticks (default matches the default background's glow)")
    ap.add_argument("--supersample", type=int, default=4)
    args = ap.parse_args()

    ss = args.supersample
    S = args.size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = cy = S / 2
    outer_r = S * 0.44
    inner_r = S * 0.27
    tick_w = S * 0.075
    r, g, b = (int(x) for x in args.color.split(","))
    n = args.ticks

    for i in range(n):
        angle = 2 * math.pi * i / n            # clockwise from 12 o'clock
        d = (n - i) % n                         # steps counter-clockwise from the head
        alpha = int(255 * (0.12 + 0.88 * (1 - d / (n - 1))))
        x0, y0 = cx + inner_r * math.sin(angle), cy - inner_r * math.cos(angle)
        x1, y1 = cx + outer_r * math.sin(angle), cy - outer_r * math.cos(angle)
        colour = (r, g, b, alpha)
        draw.line([(x0, y0), (x1, y1)], fill=colour, width=int(tick_w))
        for (x, y) in ((x0, y0), (x1, y1)):   # round caps
            draw.ellipse([x - tick_w / 2, y - tick_w / 2, x + tick_w / 2, y + tick_w / 2], fill=colour)

    img = img.resize((args.size, args.size), Image.LANCZOS)
    img.save(args.output, "PNG", optimize=True)
    print(f"wrote {args.output} ({args.size}x{args.size}, {n} ticks, colour {r},{g},{b})")


if __name__ == "__main__":
    main()
