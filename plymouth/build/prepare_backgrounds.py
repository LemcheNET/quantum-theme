#!/usr/bin/env python3
"""
Builds the two wallpaper assets the theme picks between at boot:

  theme/background-wide.png   21:9 art, used when the screen is wider than 2:1
  theme/background-16x9.png   16:9 art, used otherwise

Plymouth's script module loads PNG only, so JPEG sources are converted here
(at build time, on a machine with Pillow) rather than on the target at install
time. Metadata (EXIF etc.) is dropped; the images are flattened to RGB.

Usage:
  python3 build/prepare_backgrounds.py WIDE_SOURCE STD_SOURCE [--out-dir theme]

Status: run 2026-09-24 in the Cowork VM (Pillow) against the two source
images in src/plymouth/; outputs checked for size and mode.
"""
import argparse
import os
from PIL import Image


def convert(src, dst):
    im = Image.open(src)
    im = im.convert("RGB")                       # drop alpha/EXIF; the art is opaque
    im.save(dst, "PNG", optimize=True)
    print(f"{src} -> {dst} ({im.size[0]}x{im.size[1]}, {os.path.getsize(dst)} bytes)")
    return im.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wide_source")
    ap.add_argument("std_source")
    ap.add_argument("--out-dir", default="theme")
    a = ap.parse_args()
    w = convert(a.wide_source, os.path.join(a.out_dir, "background-wide.png"))
    s = convert(a.std_source, os.path.join(a.out_dir, "background-16x9.png"))
    if w[0] / w[1] <= 2.0:
        print("WARNING: wide source is not wider than 2:1; the theme's aspect switch assumes it is")
    if abs(s[0] / s[1] - 16 / 9) > 0.05:
        print("WARNING: standard source is not ~16:9")


if __name__ == "__main__":
    main()
