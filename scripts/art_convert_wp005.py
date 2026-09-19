#!/usr/bin/env python3
"""WP-005 automatic correction of generated facility sources (D-050).

Turns the 1254 px generated sources under docs/art/source/wp005/ into the
ArtSet file contract (docs/art/source/WP005_REQUEST.md): one 40x40 RGBA PNG
per state under assets/art/wp005/facilities/, bottom-centre ground contact,
binary alpha (no fringes), box-filtered downscale plus a small palette so the
result reads as pixel clusters rather than a blurred thumbnail. Derived
states (inactive / disconnected: lights off, desaturated, darker) are marked
DERIVED in the manifest; they are stand-ins until GPT produces dedicated
frames. This is a pilot correction, not a completed asset (ART_GUIDE: a
downscaled draft is never judged complete by itself).

    python scripts/art_convert_wp005.py [--check]

Writes the PNGs, prints a JSON record (per file: source sha256, output sha256,
bbox, scale, palette size) that the result document and the manifest quote.
"""
import hashlib
import io
import json
import os
import sys

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "art", "source", "wp005")
OUT = os.path.join(ROOT, "assets", "art", "wp005", "facilities")
CANVAS = 40
PALETTE = 24
ALPHA_THRESHOLD = 128

# asset_id -> (source file, primary state, derived state)
SOURCES = {
    "hwacha": ("hwacha_idle_source_v01.png", "idle", "inactive"),
    "jangseung": ("jangseung_idle_source_v01.png", "idle", "inactive"),
    "bongsu": ("bongsu_active_source_v01.png", "connected", "disconnected"),
    "sensor": ("sensor_active_source_v01.png", "active", "inactive"),
}


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def fit_to_canvas(src):
    """Crop to the alpha bounds, scale the longer side to the canvas, keep the
    aspect ratio, sit the object on the canvas bottom, centred horizontally."""
    bbox = src.getbbox()
    crop = src.crop(bbox)
    w, h = crop.size
    scale = CANVAS / float(max(w, h))
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    small = crop.resize((nw, nh), Image.BOX)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(small, ((CANVAS - nw) // 2, CANVAS - nh))
    return canvas, bbox, scale


def quantize_keep_alpha(img, colors):
    rgb = img.convert("RGB")
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    alpha = img.getchannel("A").point(lambda a: 255 if a >= ALPHA_THRESHOLD else 0)
    out = q.copy()
    out.putalpha(alpha)
    # fully transparent pixels carry no colour (clean edges, deterministic sha)
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y][3] == 0:
                px[x, y] = (0, 0, 0, 0)
    # the binary alpha may have eaten the soft bottom / side rows: re-seat the
    # opaque silhouette on the canvas bottom, centred (ground-contact pivot)
    bb = out.getbbox()
    if bb:
        obj = out.crop(bb)
        seated = Image.new("RGBA", out.size, (0, 0, 0, 0))
        seated.paste(obj, ((out.width - obj.width) // 2, out.height - obj.height))
        out = seated
    return out


def derive_off(img):
    """Lights-off stand-in: desaturate and darken, keep the silhouette."""
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(0.25)
    rgb = ImageEnhance.Brightness(rgb).enhance(0.72)
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def main():
    check = "--check" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    record = []
    for asset_id, (src_name, state, derived) in SOURCES.items():
        src_path = os.path.join(SRC, src_name)
        src = Image.open(src_path).convert("RGBA")
        fitted, bbox, scale = fit_to_canvas(src)
        primary = quantize_keep_alpha(fitted, PALETTE)
        off = derive_off(primary)
        for st, img, kind in ((state, primary, "downscaled"), (derived, off, "derived_off")):
            name = "%s_%s_v01.png" % (asset_id, st)
            path = os.path.join(OUT, name)
            buf = io.BytesIO()
            img.save(buf, "PNG", optimize=True)
            data = buf.getvalue()
            if check:
                ok = os.path.exists(path) and open(path, "rb").read() == data
                record.append({"file": name, "unchanged": ok})
                continue
            with open(path, "wb") as f:
                f.write(data)
            colors = len(set(img.get_flattened_data())) if hasattr(img, "get_flattened_data") else len(set(img.getdata()))
            record.append({
                "asset_id": asset_id, "state": st, "kind": kind, "file": os.path.relpath(path, ROOT).replace("\\", "/"),
                "source": os.path.relpath(src_path, ROOT).replace("\\", "/"), "source_sha256": sha256(src_path),
                "source_alpha_bbox": list(bbox), "scale": round(scale, 5), "canvas": [CANVAS, CANVAS],
                "pivot": [CANVAS / 2, CANVAS - 20], "distinct_colours": colors, "sha256": hashlib.sha256(data).hexdigest(),
            })
    print(json.dumps(record, indent=1, ensure_ascii=False))
    if check and not all(r["unchanged"] for r in record):
        sys.exit(1)


if __name__ == "__main__":
    main()
