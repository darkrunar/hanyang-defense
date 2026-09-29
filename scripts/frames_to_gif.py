"""Turn a Godot movie-maker PNG sequence into a small animated GIF.

    python scripts/frames_to_gif.py <frame_dir> <out.gif> [--scale 0.5] [--every 2] [--fps-in 20]

Used for LD-DEV-01 route-preview clips (editor preview, not battle footage).
Needs Pillow.
"""
import argparse
import glob
import os
import sys

from PIL import Image


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("out")
    ap.add_argument("--scale", type=float, default=0.5)
    ap.add_argument("--every", type=int, default=2, help="keep every n-th frame")
    ap.add_argument("--fps-in", type=float, default=20.0, help="fixed fps the frames were written at")
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.frames, "*.png")))
    if not files:
        print("no frames in", a.frames)
        return 1
    kept = files[:: max(a.every, 1)]
    frames = []
    for f in kept:
        im = Image.open(f).convert("RGB")
        if a.scale != 1.0:
            im = im.resize((round(im.width * a.scale), round(im.height * a.scale)), Image.LANCZOS)
        # Octree keeps small saturated marks (red preview dots) that median cut greys out.
        frames.append(im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE))
    duration_ms = round(1000.0 * max(a.every, 1) / a.fps_in)
    frames[0].save(a.out, save_all=True, append_images=frames[1:], duration=duration_ms, loop=0, optimize=True)
    print("%s: %d frames of %d, %d ms each, %dx%d, %d bytes" % (
        os.path.basename(a.out), len(frames), len(files), duration_ms, frames[0].width, frames[0].height,
        os.path.getsize(a.out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
