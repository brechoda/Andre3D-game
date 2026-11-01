#!/usr/bin/env python3
"""Export RenderWare DFF geometry to Godot-importable OBJ/MTL files.

This intentionally handles static world meshes first. It preserves vertex positions,
UV layers and material texture names; animation/skinning is outside the map pipeline.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def safe_name(name: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", name).strip("._")
    return value or "unnamed"


def texture_lookup(texture_root: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    if not texture_root.exists():
        return result
    for path in texture_root.rglob("*.PNG"):
        result.setdefault(path.stem.casefold(), path)
    return result


def export_one(source: Path, output: Path, texture_root: Path) -> dict:
    try:
        from gtaLib.dff import dff
    except ImportError as exc:
        raise RuntimeError("DragonFF is required; pass --dragonff pointing to its checkout") from exc
    archive = dff()
    archive.load_file(str(source))
    geometries = []
    for clump in archive.clumps:
        geometries.extend(clump.geometry_list)
    if not geometries:
        raise RuntimeError(f"No geometry found in {source.name}")

    output.parent.mkdir(parents=True, exist_ok=True)
    obj_path = output.with_suffix(".obj")
    mtl_path = output.with_suffix(".mtl")
    lookup = texture_lookup(texture_root)
    vertices = []
    uvs = []
    faces = []
    materials: dict[str, str | None] = {}
    for geom_index, geom in enumerate(geometries):
        layer = geom.uv_layers[0] if geom.uv_layers else []
        base = len(vertices)
        vertices.extend((float(v.x), float(v.y), float(v.z)) for v in geom.vertices)
        uvs.extend((float(uv.u), 1.0 - float(uv.v)) for uv in layer)
        if len(uvs) < len(vertices):
            uvs.extend((0.0, 0.0) for _ in range(len(vertices) - len(uvs)))
        material_names = []
        for mat_index, material in enumerate(geom.materials):
            mat_name = f"mat_{geom_index}_{mat_index}"
            tex_name = material.textures[0].name if material.textures else ""
            texture_path = lookup.get(tex_name.casefold())
            materials[mat_name] = texture_path.name if texture_path else None
            material_names.append(mat_name)
        for tri in geom.triangles:
            mat_index = int(tri.material)
            mat_name = material_names[mat_index] if 0 <= mat_index < len(material_names) else "mat_default"
            materials.setdefault(mat_name, None)
            # RenderWare triangles refer to the position/UV arrays with the same index.
            indices = [base + int(tri.a) + 1, base + int(tri.b) + 1, base + int(tri.c) + 1]
            faces.append((mat_name, indices))

    with mtl_path.open("w", encoding="utf-8") as mtl:
        for mat_name, texture_name in materials.items():
            mtl.write(f"newmtl {mat_name}\nKd 1.0 1.0 1.0\nKa 0.0 0.0 0.0\n")
            if texture_name:
                mtl.write(f"map_Kd {texture_name}\n")
            mtl.write("\n")
    with obj_path.open("w", encoding="utf-8") as obj:
        obj.write(f"mtllib {mtl_path.name}\no {safe_name(source.stem)}\n")
        for x, y, z in vertices:
            obj.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
        for u, v in uvs:
            obj.write(f"vt {u:.6f} {v:.6f}\n")
        active = None
        for mat_name, indices in faces:
            if mat_name != active:
                obj.write(f"usemtl {mat_name}\n")
                active = mat_name
            obj.write("f " + " ".join(f"{i}/{i}" for i in indices) + "\n")
    return {"source": source.name, "output": obj_path.name, "vertices": len(vertices), "faces": len(faces), "materials": len(materials)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dragonff", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--textures", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.dragonff))
    result = export_one(args.input, args.output, args.textures)
    print(result)


if __name__ == "__main__":
    main()
