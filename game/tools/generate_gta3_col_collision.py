#!/usr/bin/env python3
"""Bake GTA III COL1 models into per-IPL-tile collision meshes.

The source COL files contain local model collision geometry. This tool applies
all map_manifest IPL transforms, including scale and quaternion rotation, and
writes one OBJ per streamed tile. The OBJ files are collision-only assets: no
materials or textures are referenced.

Dependency: pip install rwfury
"""
from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

from rwfury import Col


def mul(m, v):
    return (
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    )


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def quat_matrix(q):
    x, y, z, w = (float(v) for v in q)
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    return (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )


def tile_key(source: str) -> str:
    parts = [p for p in source.replace("\\", "/").split("/") if p]
    if len(parts) >= 2:
        return f"{parts[-2].lower()}_{Path(parts[-1]).stem.lower()}"
    return Path(parts[-1]).stem.lower() if parts else "unknown"


def cube_faces(base: int):
    return [(base + a, base + b, base + c) for a, b, c in (
        (0, 1, 2), (0, 2, 3), (4, 6, 5), (4, 7, 6),
        (0, 4, 5), (0, 5, 1), (1, 5, 6), (1, 6, 2),
        (2, 6, 7), (2, 7, 3), (3, 7, 4), (3, 4, 0),
    )]


def sphere_geometry(center, radius, rings=6, segments=12):
    vertices = []
    faces = []
    for ring in range(rings + 1):
        phi = math.pi * ring / rings
        sp, cp = math.sin(phi), math.cos(phi)
        for segment in range(segments):
            theta = 2.0 * math.pi * segment / segments
            vertices.append((center[0] + radius * sp * math.cos(theta),
                             center[1] + radius * sp * math.sin(theta),
                             center[2] + radius * cp))
    for ring in range(rings):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.extend(((a, b, c), (a, c, d)))
    return vertices, faces


def transformed(local, rot, pos, scale):
    scaled = (local[0] * scale[0], local[1] * scale[1], local[2] * scale[2])
    return add(mul(rot, scaled), pos)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--col-root", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--model-filter", type=Path, help="JSON list of tree and pole models whose collision placements should be omitted")
    args = ap.parse_args()

    excluded_models = set()
    if args.model_filter:
        filter_data = json.loads(args.model_filter.read_text(encoding="utf-8"))
        excluded_models = {str(name).casefold() for key in ("trees", "poles") for name in filter_data.get(key, [])}

    model_index = {}
    source_files = 0
    for path in sorted(args.col_root.rglob("*.col")):
        collision = Col.from_file(str(path))
        source_files += 1
        for model in collision.models:
            model_index[model.name.casefold()] = model

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    grouped = defaultdict(list)
    for placement in manifest["placements"]:
        grouped[tile_key(str(placement.get("source", "unknown.ipl")))].append(placement)

    args.output.mkdir(parents=True, exist_ok=True)
    report = {"schema": 1, "source_files": source_files, "tiles": [], "missing_models": [],
              "excluded_model_count": len(excluded_models), "excluded_placements": 0}
    for tile, placements in sorted(grouped.items()):
        vertices = []
        faces = []
        matched = 0
        primitive_count = 0
        excluded_in_tile = 0
        for placement in placements:
            model_name = str(placement.get("model", ""))
            if model_name.casefold() in excluded_models:
                excluded_in_tile += 1
                continue
            model = model_index.get(model_name.casefold())
            if model is None:
                report["missing_models"].append(model_name)
                continue
            matched += 1
            rot = quat_matrix(placement.get("rotation", [0, 0, 0, 1]))
            pos = tuple(float(v) for v in placement.get("position", [0, 0, 0]))
            scale = tuple(float(v) for v in placement.get("scale", [1, 1, 1]))
            vertices.extend(transformed(v, rot, pos, scale) for v in model.vertices)
            faces.extend((len(vertices) - len(model.vertices) + f.a,
                          len(vertices) - len(model.vertices) + f.b,
                          len(vertices) - len(model.vertices) + f.c) for f in model.faces)
            for box in model.boxes:
                box_base = len(vertices)
                corners = (
                    (box.min[0], box.min[1], box.min[2]), (box.max[0], box.min[1], box.min[2]),
                    (box.max[0], box.max[1], box.min[2]), (box.min[0], box.max[1], box.min[2]),
                    (box.min[0], box.min[1], box.max[2]), (box.max[0], box.min[1], box.max[2]),
                    (box.max[0], box.max[1], box.max[2]), (box.min[0], box.max[1], box.max[2]),
                )
                vertices.extend(transformed(v, rot, pos, scale) for v in corners)
                faces.extend(cube_faces(box_base))
                primitive_count += 1
            for sphere in model.spheres:
                sphere_base = len(vertices)
                sphere_vertices, sphere_faces = sphere_geometry(sphere.center, sphere.radius)
                vertices.extend(transformed(v, rot, pos, scale) for v in sphere_vertices)
                faces.extend((sphere_base + a, sphere_base + b, sphere_base + c) for a, b, c in sphere_faces)
                primitive_count += 1

        report["excluded_placements"] += excluded_in_tile
        obj_path = args.output / f"{tile}.obj"
        with obj_path.open("w", encoding="utf-8") as out:
            out.write(f"o {tile}_COL1\n")
            for x, y, z in vertices:
                out.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for a, b, c in faces:
                out.write(f"f {a + 1} {b + 1} {c + 1}\n")
        row = {"tile": tile, "placements": len(placements), "excluded_placements": excluded_in_tile,
               "matched": matched, "vertices": len(vertices), "faces": len(faces),
               "primitives": primitive_count, "obj": obj_path.name}
        report["tiles"].append(row)
        print(json.dumps(row), flush=True)

    report["missing_models"] = sorted(set(report["missing_models"]))
    (args.output / "collision_manifest.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"tiles": len(report["tiles"]), "missing_models": len(report["missing_models"]),
                      "excluded_placements": report["excluded_placements"]}, indent=2))


if __name__ == "__main__":
    main()
