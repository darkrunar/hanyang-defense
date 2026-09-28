#!/usr/bin/env python3
"""WP-005 derived facility states (D-050 / D-051).

The primary contract files (idle / active / connected, 40x40) are produced
from the generated sources by game/tools/import_wp005_sources.gd (PR #11).
This script derives the lights-off stand-ins from THOSE files: inactive /
disconnected = same silhouette, desaturated and darker, marked derived_off
in the manifest. They are placeholders until GPT delivers dedicated frames;
nothing here is judged a completed asset (ART_GUIDE).

    python scripts/art_convert_wp005.py [--check]

Writes the derived PNGs and prints a JSON record (per file: primary sha256,
output sha256) that the result document and the manifest quote. --check
verifies the files on disk are exactly what the script would write.
"""
import hashlib
import io
import json
import os
import sys

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "art", "wp005", "facilities")
CANVAS = 40

# asset_id -> (primary state file produced by import_wp005_sources.gd, derived state)
SOURCES = {
    "hwacha": ("idle", "inactive"),
    "jangseung": ("idle", "inactive"),
    "bongsu": ("connected", "disconnected"),
    "sensor": ("active", "inactive"),
}


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def derive_off(img):
    """Lights-off stand-in: desaturate and darken, keep the silhouette."""
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(0.25)
    rgb = ImageEnhance.Brightness(rgb).enhance(0.72)
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y][3] == 0:
                px[x, y] = (0, 0, 0, 0)
    return out


def main():
    check = "--check" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    record = []
    for asset_id, (state, derived) in SOURCES.items():
        # Dedicated generated states supersede the D-051 derived placeholders.
        # Never overwrite them with desaturation when this legacy tool is run.
        dedicated = os.path.join(ROOT, "docs", "art", "source", "wp005", "%s_%s_source_v01.png" % (asset_id, derived))
        if os.path.exists(dedicated):
            path = os.path.join(OUT, "%s_%s_v01.png" % (asset_id, derived))
            manifest_path = os.path.join(ROOT, "assets", "art", "wp005", "integration_manifest.json")
            with open(manifest_path, encoding="utf-8") as f:
                manifest = json.load(f)
            expected = next((x["sha256"] for x in manifest["loaded"] if x["asset_id"] == asset_id and x["state"] == derived), None)
            valid = os.path.exists(path) and sha256(path) == expected
            if not valid:
                raise RuntimeError("Run Godot import_wp005_sources.gd to rebuild dedicated states")
            record.append({"file": os.path.basename(path), "kind": "dedicated_generated", "unchanged": True})
            continue
        src_path = os.path.join(OUT, "%s_%s_v01.png" % (asset_id, state))
        primary = Image.open(src_path).convert("RGBA")
        assert primary.size == (CANVAS, CANVAS), src_path
        img = derive_off(primary)
        name = "%s_%s_v01.png" % (asset_id, derived)
        path = os.path.join(OUT, name)
        buf = io.BytesIO()
        img.save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        if check:
            record.append({"file": name, "unchanged": os.path.exists(path) and open(path, "rb").read() == data})
            continue
        with open(path, "wb") as f:
            f.write(data)
        colors = len(set(img.get_flattened_data())) if hasattr(img, "get_flattened_data") else len(set(img.getdata()))
        record.append({
            "asset_id": asset_id, "state": derived, "kind": "derived_off", "file": os.path.relpath(path, ROOT).replace("\\", "/"),
            "primary": os.path.relpath(src_path, ROOT).replace("\\", "/"), "primary_sha256": sha256(src_path),
            "canvas": [CANVAS, CANVAS], "pivot": [CANVAS / 2, CANVAS - 20], "distinct_colours": colors,
            "sha256": hashlib.sha256(data).hexdigest(),
        })
    print(json.dumps(record, indent=1, ensure_ascii=False))
    if check and not all(r["unchanged"] for r in record):
        sys.exit(1)


if __name__ == "__main__":
    main()
