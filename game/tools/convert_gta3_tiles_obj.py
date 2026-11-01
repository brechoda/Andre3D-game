#!/usr/bin/env python3
"""Convert GTA III DFF placements into one textured OBJ/MTL mesh per IPL tile."""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Mat:
    name: str
    texture_path: Path | None


def safe(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("._")
    return value or "unnamed"


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(m, v):
    return (
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    )


def matmul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def frame_matrix(frame):
    rows = frame.rotation_matrix
    return tuple(tuple(float(getattr(rows[i], axis)) for axis in ("x", "y", "z")) for i in range(3))


def world_frames(frames):
    cache = {}
    def resolve(index):
        if index in cache:
            return cache[index]
        frame = frames[index]
        local_m = frame_matrix(frame)
        local_p = tuple(float(x) for x in frame.position)
        parent = int(frame.parent)
        if parent >= 0 and parent < len(frames):
            parent_m, parent_p = resolve(parent)
            result = (matmul(parent_m, local_m), add(mul(parent_m, local_p), parent_p))
        else:
            result = (local_m, local_p)
        cache[index] = result
        return result
    return [resolve(i) for i in range(len(frames))]


def quat_matrix(q):
    x, y, z, w = (float(v) for v in q)
    n = math.sqrt(x*x + y*y + z*z + w*w) or 1.0
    x, y, z, w = x/n, y/n, z/n, w/n
    return (
        (1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)),
        (2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)),
        (2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y)),
    )


def texture_lookup(root: Path) -> dict[str, Path]:
    result = {}
    for p in root.rglob("*.PNG"):
        result.setdefault(p.stem.casefold(), p)
    return result


def find_dffs(root: Path) -> dict[str, Path]:
    return {p.stem.casefold(): p for p in root.glob("*.dff")}


def prepare_model(path: Path, texture_paths: dict[str, Path]):
    from gtaLib.dff import dff
    archive = dff()
    archive.load_file(str(path))
    prepared = []
    for clump in archive.clumps:
        frames = world_frames(clump.frame_list)
        for atomic in clump.atomic_list:
            geometry = clump.geometry_list[int(atomic.geometry)]
            frame_index = int(atomic.frame)
            frame_m, frame_p = frames[frame_index] if 0 <= frame_index < len(frames) else (((1,0,0),(0,1,0),(0,0,1)), (0,0,0))
            mats = []
            for i, material in enumerate(geometry.materials):
                tex_name = material.textures[0].name if material.textures else ""
                tex = texture_paths.get(tex_name.casefold())
                mats.append(Mat(f"{safe(path.stem)}_m{i}_{safe(tex_name)}", tex))
            uv_layer = geometry.uv_layers[0] if geometry.uv_layers else []
            local_vertices = []
            for v in geometry.vertices:
                local = (float(v.x), float(v.y), float(v.z))
                local_vertices.append(add(mul(frame_m, local), frame_p))
            faces = []
            for tri in geometry.triangles:
                mi = int(tri.material)
                mat = mats[mi] if 0 <= mi < len(mats) else Mat(f"{safe(path.stem)}_default", None)
                faces.append((int(tri.a), int(tri.b), int(tri.c), mat.name))
            uvs = [(float(uv.u), 1.0 - float(uv.v)) for uv in uv_layer]
            prepared.append((local_vertices, uvs, faces, mats))
    return prepared


def tile_key(source: str) -> str:
    parts = [p for p in source.replace("\\", "/").split("/") if p]
    if len(parts) >= 2:
        return f"{parts[-2].lower()}_{Path(parts[-1]).stem.lower()}"
    return safe(Path(parts[-1]).stem if parts else "unknown")


def convert(manifest_path: Path, dff_root: Path, texture_root: Path, output_root: Path) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    dffs = find_dffs(dff_root)
    textures = texture_lookup(texture_root)
    grouped = defaultdict(list)
    for placement in manifest["placements"]:
        grouped[tile_key(str(placement.get("source", "unknown.ipl")))].append(placement)
    errors = []
    model_cache = {}
    results = []
    for tile, placements in sorted(grouped.items()):
        vertices = []
        uvs = []
        faces = []
        materials = {}
        for placement in placements:
            model_name = str(placement.get("model", ""))
            source = dffs.get(model_name.casefold())
            if source is None:
                errors.append({"tile": tile, "model": model_name, "error": "DFF not found"})
                continue
            try:
                if source.name.casefold() not in model_cache:
                    model_cache[source.name.casefold()] = prepare_model(source, textures)
                model_parts = model_cache[source.name.casefold()]
            except Exception as exc:
                errors.append({"tile": tile, "model": model_name, "error": repr(exc)})
                continue
            rot = quat_matrix(placement.get("rotation", [0, 0, 0, 1]))
            pos = tuple(float(v) for v in placement.get("position", [0, 0, 0]))
            scale = tuple(float(v) for v in placement.get("scale", [1, 1, 1]))
            for local_vertices, local_uvs, local_faces, local_mats in model_parts:
                base = len(vertices)
                for local in local_vertices:
                    scaled = (local[0] * scale[0], local[1] * scale[1], local[2] * scale[2])
                    vertices.append(add(mul(rot, scaled), pos))
                uv_base = len(uvs)
                uvs.extend(local_uvs if local_uvs else [(0.0, 0.0)] * len(local_vertices))
                for mat in local_mats:
                    materials[mat.name] = mat.texture_path
                for a, b, c, mat_name in local_faces:
                    faces.append((mat_name, (base + a + 1, base + b + 1, base + c + 1), (uv_base + a + 1, uv_base + b + 1, uv_base + c + 1)))
        output_root.mkdir(parents=True, exist_ok=True)
        obj = output_root / f"{tile}.obj"
        mtl = output_root / f"{tile}.mtl"
        with mtl.open("w", encoding="utf-8") as f:
            for name, tex in sorted(materials.items()):
                f.write(f"newmtl {name}\nKd 1.0 1.0 1.0\nKa 0.0 0.0 0.0\n")
                if tex:
                    rel = Path("../textures") / tex.relative_to(texture_root)
                    f.write(f"map_Kd {rel.as_posix()}\n")
                f.write("\n")
        with obj.open("w", encoding="utf-8") as f:
            f.write(f"mtllib {mtl.name}\no {tile}\n")
            for x, y, z in vertices:
                f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for u, v in uvs:
                f.write(f"vt {u:.6f} {v:.6f}\n")
            active = None
            for mat_name, vi, ti in faces:
                if mat_name != active:
                    f.write(f"usemtl {mat_name}\n")
                    active = mat_name
                f.write("f " + " ".join(f"{v}/{t}" for v, t in zip(vi, ti)) + "\n")
        results.append({"tile": tile, "placements": len(placements), "vertices": len(vertices), "faces": len(faces), "materials": len(materials), "obj": obj.name})
        print(json.dumps(results[-1]), flush=True)
    report = {"schema": 1, "tiles": results, "errors": errors, "models_parsed": len(model_cache)}
    (output_root / "conversion_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dragonff", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--dffs", type=Path, required=True)
    parser.add_argument("--textures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.dragonff))
    report = convert(args.manifest, args.dffs, args.textures, args.output)
    print(json.dumps({"models_parsed": report["models_parsed"], "tiles": len(report["tiles"]), "errors": len(report["errors"])}, indent=2))


if __name__ == "__main__":
    main()
