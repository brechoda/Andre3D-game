#!/usr/bin/env python3
"""Repair the malformed subglass TXD and annotate map materials with alpha assets.

The extracted mobile subglass.txd contains only a truncated 36-byte TXD header.
The two affected DFFs are simple glass planes, so this produces small, explicit
replacement textures with real alpha and rewrites all generated MTL references.
Runtime alpha mode is applied by gta3_map_streamer.gd after OBJ import.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


def make_glass(path: Path, tint: tuple[int, int, int], seed: int) -> None:
    size = 64
    image = Image.new("RGBA", (size, size), (*tint, 0))
    px = image.load()
    for y in range(size):
        for x in range(size):
            diagonal = (x + y + seed * 7) % 32
            edge = min(x, y, size - 1 - x, size - 1 - y)
            alpha = 82 + int(34 * (1.0 - diagonal / 31.0))
            if edge < 2:
                alpha += 20
            px[x, y] = (*tint, max(48, min(156, alpha)))
    draw = ImageDraw.Draw(image)
    draw.line((0, size - 1, size - 1, 0), fill=(220, 245, 255, 120), width=1)
    image.save(path, format="PNG", optimize=True)


def patch_mtls(mtl_root: Path, texture_root: Path) -> int:
    replacements = {
        "glassfxsub1_m0_unnamed": "../textures/subglass/glassfxsub1.PNG",
        "glassfxsub2_m0_unnamed": "../textures/subglass/glassfxsub2.PNG",
    }
    changed = 0
    for path in mtl_root.rglob("*.mtl"):
        lines = path.read_text(encoding="utf-8").splitlines()
        out: list[str] = []
        active = ""
        block_has_map = False
        block_has_opacity = False
        touched = False
        def finish_block() -> None:
            nonlocal block_has_map, block_has_opacity, touched
            if active in replacements and not block_has_map:
                out.append("map_Kd " + replacements[active])
                out.append("d 0.52")
                out.append("Tr 0.48")
                touched = True
            block_has_map = False
            block_has_opacity = False

        for line in lines:
            if line.startswith("newmtl "):
                if active:
                    finish_block()
                active = line[7:].strip()
            elif line.startswith("map_Kd ") and active in replacements:
                line = "map_Kd " + replacements[active]
                block_has_map = True
                touched = True
            elif line.startswith(("d ", "Tr ")) and active in replacements:
                block_has_opacity = True
            out.append(line)
        if active:
            finish_block()
        if touched:
            path.write_text("\n".join(out) + "\n", encoding="utf-8")
            changed += 1
    return changed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-txd", type=Path, required=True)
    parser.add_argument("--mtl-root", type=Path, required=True)
    parser.add_argument("--texture-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    out = args.texture_root / "subglass"
    out.mkdir(parents=True, exist_ok=True)
    make_glass(out / "glassfxsub1.PNG", (115, 172, 194), 1)
    make_glass(out / "glassfxsub2.PNG", (86, 135, 160), 2)
    changed = patch_mtls(args.mtl_root, args.texture_root)
    source_size = args.source_txd.stat().st_size
    report = {
        "source": str(args.source_txd),
        "source_size_bytes": source_size,
        "source_valid_txd": False,
        "replacement_textures": [
            "subglass/glassfxsub1.PNG",
            "subglass/glassfxsub2.PNG",
        ],
        "patched_mtl_files": changed,
        "alpha_mode": "runtime_alpha_for_textures_with_alpha_channel",
    }
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
