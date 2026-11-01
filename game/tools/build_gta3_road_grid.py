#!/usr/bin/env python3
"""Build a compact road-only GPS grid and minimap from converted GTA III OBJ tiles.

The output is derived from surfaces whose MTL names identify actual road pavement
or lane markings. It uses no network access and does not modify the source tiles.
"""
from __future__ import annotations

import argparse
import base64
import json
import math
import re
import zlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROAD_TEXTURE_PREFIXES = (
    "road_1line",
    "road_2line",
    "road_blank",
    "road_cross",
    "road_yellowline",
    "road_pavetrans",
    "road_nolinescob",
    "broadw_new",
    "broadway",
    "concroadslab_",
    "raiseroad_section",
)
MATERIAL_SUFFIX = re.compile(r"_m\d+_(.+)$", re.IGNORECASE)


def is_drive_surface(material: str) -> bool:
    match = MATERIAL_SUFFIX.search(material)
    if not match:
        return False
    suffix = match.group(1).casefold()
    return suffix.startswith(ROAD_TEXTURE_PREFIXES)


def tile_bounds(catalog_path: Path) -> tuple[float, float, float, float]:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    tiles = catalog.get("tiles", [])
    if not tiles:
        raise ValueError(f"No tiles in {catalog_path}")
    min_x = min(float(tile["bounds_min"][0]) for tile in tiles)
    min_y = min(float(tile["bounds_min"][1]) for tile in tiles)
    max_x = max(float(tile["bounds_max"][0]) for tile in tiles)
    max_y = max(float(tile["bounds_max"][1]) for tile in tiles)
    return min_x, min_y, max_x, max_y


def resolve_obj_vertex(raw_index: str, vertex_count: int) -> int:
    index = int(raw_index)
    return index - 1 if index > 0 else vertex_count + index


def rasterize_obj(obj_path: Path, draw: ImageDraw.ImageDraw,
                  min_x: float, max_y: float, cell_size: float,
                  width: int, height: int) -> tuple[int, int]:
    vertices: list[tuple[float, float, float]] = []
    active_road_material = False
    road_faces = 0
    road_triangles = 0
    with obj_path.open("r", encoding="utf-8", errors="ignore") as source:
        for raw_line in source:
            if raw_line.startswith("v "):
                parts = raw_line.split()
                if len(parts) >= 4:
                    try:
                        vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
                    except ValueError:
                        vertices.append((0.0, 0.0, 0.0))
            elif raw_line.startswith("usemtl "):
                active_road_material = is_drive_surface(raw_line[7:].strip())
            elif active_road_material and raw_line.startswith("f "):
                tokens = raw_line.split()[1:]
                if len(tokens) < 3:
                    continue
                points: list[tuple[int, int]] = []
                try:
                    for token in tokens:
                        vertex_index = resolve_obj_vertex(token.split("/", 1)[0], len(vertices))
                        x, y, _z = vertices[vertex_index]
                        px = int(round((x - min_x) / cell_size))
                        py = int(round((max_y - y) / cell_size))
                        points.append((px, py))
                except (IndexError, ValueError, ZeroDivisionError):
                    continue
                if len(points) >= 3:
                    draw.polygon(points, fill=255)
                    # Seal sub-cell cracks along pavement triangle boundaries.
                    draw.line(points + [points[0]], fill=255, width=1)
                    road_faces += 1
                    road_triangles += len(points) - 2
    return road_faces, road_triangles


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True,
                        help="Directory containing converted tile OBJ files")
    parser.add_argument("--catalog", type=Path, required=True,
                        help="gta3_tile_catalog.json for source-coordinate bounds")
    parser.add_argument("--output", type=Path, required=True,
                        help="Runtime map directory for road_grid.json and road_map.png")
    parser.add_argument("--cell-size", type=float, default=4.0,
                        help="Meters per grid cell (default: 4m for mobile memory budget)")
    args = parser.parse_args()
    if args.cell_size <= 0.0:
        raise ValueError("--cell-size must be positive")

    min_x, min_y, max_x, max_y = tile_bounds(args.catalog)
    width = int(math.ceil((max_x - min_x) / args.cell_size)) + 1
    height = int(math.ceil((max_y - min_y) / args.cell_size)) + 1
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    face_total = 0
    triangle_total = 0
    obj_files = sorted(args.source.glob("*.obj"))
    if not obj_files:
        raise FileNotFoundError(f"No OBJ tiles in {args.source}")

    for index, obj_path in enumerate(obj_files, start=1):
        faces, triangles = rasterize_obj(
            obj_path, draw, min_x, max_y, args.cell_size, width, height
        )
        face_total += faces
        triangle_total += triangles
        print(f"[{index}/{len(obj_files)}] {obj_path.name}: road faces={faces}, triangles={triangles}", flush=True)

    raw_mask = mask.tobytes()
    road_cells = sum(1 for value in raw_mask if value)
    if road_cells == 0:
        raise RuntimeError("No road cells were rasterized; check OBJ material names")

    args.output.mkdir(parents=True, exist_ok=True)
    road_map = ImageOps.colorize(mask, black="#08141d", white="#9bb7bb").convert("RGB")
    road_map.save(args.output / "road_map.png", optimize=True)

    compressed = zlib.compress(raw_mask, level=9)
    metadata = {
        "schema": 1,
        "source": "converted_tiles OBJ road-surface materials",
        "coordinate_system": "GTA III source XY; image row 0 is max_y",
        "bounds": {"min_x": min_x, "min_y": min_y, "max_x": max_x, "max_y": max_y},
        "cell_size": args.cell_size,
        "width": width,
        "height": height,
        "road_cells": road_cells,
        "road_faces": face_total,
        "road_triangles": triangle_total,
        "mask_codec": "zlib+base64; 0=blocked, 255=road",
        "mask_zlib_base64": base64.b64encode(compressed).decode("ascii"),
    }
    (args.output / "road_grid.json").write_text(
        json.dumps(metadata, separators=(",", ":")), encoding="utf-8"
    )
    print(
        f"DONE grid={width}x{height} cell={args.cell_size:g}m "
        f"road_cells={road_cells} faces={face_total} triangles={triangle_total} "
        f"raw={len(raw_mask)} compressed={len(compressed)} "
        f"output={args.output}",
        flush=True,
    )


if __name__ == "__main__":
    main()
