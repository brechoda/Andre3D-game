#!/usr/bin/env python3
"""Split converted GTA III OBJ tiles into Godot-safe, texture-correct meshes."""
from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path
from collections import OrderedDict


def read_materials(path: Path) -> dict[str, list[str]]:
    materials: dict[str, list[str]] = {}
    active: str | None = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("newmtl "):
            active = line[7:].strip()
            materials[active] = [line]
        elif active is not None and line:
            if line.startswith("map_Kd "):
                texture = line[7:].strip().replace("\\", "/")
                if texture.startswith("../../textures/"):
                    texture = texture[len("../../textures/"):]
                elif texture.startswith("../textures/"):
                    texture = texture[len("../textures/"):]
                materials[active].append("map_Kd ../textures/" + texture)
            else:
                materials[active].append(line)
    return materials


def load_model_filter(path: Path | None) -> dict:
    if path is None:
        return {"models": set(), "keywords": (), "preserve_prefixes": ()}
    data = json.loads(path.read_text(encoding="utf-8"))
    models = {str(name).casefold() for key in ("trees", "poles") for name in data.get(key, [])}
    return {
        "models": models,
        "keywords": tuple(str(x).casefold() for x in data.get("tree_surface_material_keywords", [])),
        "preserve_prefixes": tuple(str(x).casefold() for x in data.get("preserve_surface_model_prefixes", [])),
    }


def material_is_excluded(material_name: str, model_filter: dict) -> bool:
    match = re.match(r"(.+?)_m\d+_", material_name, flags=re.IGNORECASE)
    model_name = match.group(1).casefold() if match else ""
    if model_name in model_filter["models"]:
        return True
    if model_name and any(model_name.startswith(prefix) for prefix in model_filter["preserve_prefixes"]):
        return False
    lowered = material_name.casefold()
    return any(keyword in lowered for keyword in model_filter["keywords"])


def split_tile(obj_path: Path, output_dir: Path, tile_name: str, material_limit: int, model_filter: dict) -> dict:
    mtl_path = obj_path.with_suffix(".mtl")
    if not mtl_path.is_file():
        raise FileNotFoundError(f"Missing material file: {mtl_path}")
    materials = read_materials(mtl_path)
    excluded_materials = {name for name in materials if material_is_excluded(name, model_filter)}
    vertices: list[str] = []
    uvs: list[str] = []
    faces_by_material: OrderedDict[str, list[tuple[tuple[int, int, int], tuple[int, int, int]]]] = OrderedDict()
    active_material: str | None = None
    face_count = 0
    excluded_face_count = 0
    seen_excluded_materials: set[str] = set()
    with obj_path.open("r", encoding="utf-8", errors="replace") as source:
        for raw in source:
            if raw.startswith("v "):
                vertices.append(raw.rstrip("\n"))
            elif raw.startswith("vt "):
                uvs.append(raw.rstrip("\n"))
            elif raw.startswith("usemtl "):
                active_material = raw[7:].strip()
                if active_material in excluded_materials:
                    seen_excluded_materials.add(active_material)
                else:
                    faces_by_material.setdefault(active_material, [])
            elif raw.startswith("f "):
                if active_material is None:
                    raise ValueError(f"Face before usemtl in {obj_path}")
                if active_material in excluded_materials:
                    excluded_face_count += 1
                    continue
                tokens = raw.split()[1:]
                if len(tokens) != 3:
                    raise ValueError(f"Expected triangle face in {obj_path}: {raw[:100]}")
                v_indices: list[int] = []
                uv_indices: list[int] = []
                for token in tokens:
                    pair = token.split("/")
                    v_indices.append(int(pair[0]))
                    uv_indices.append(int(pair[1]) if len(pair) > 1 and pair[1] else 0)
                if any(index <= 0 or index > len(vertices) for index in v_indices):
                    raise ValueError(f"Invalid vertex reference in {obj_path}")
                if any(index <= 0 or index > len(uvs) for index in uv_indices):
                    raise ValueError(f"Invalid UV reference in {obj_path}")
                faces_by_material[active_material].append((tuple(v_indices), tuple(uv_indices)))
                face_count += 1

    used_materials = [name for name, faces in faces_by_material.items() if faces]
    output_dir.mkdir(parents=True, exist_ok=True)
    part_files: list[str] = []
    part_summaries: list[dict] = []
    for part_number, start in enumerate(range(0, len(used_materials), material_limit)):
        batch = used_materials[start : start + material_limit]
        stem = f"{tile_name}__part_{part_number:02d}"
        part_obj = output_dir / f"{stem}.obj"
        part_mtl = output_dir / f"{stem}.mtl"
        local_vertices: list[str] = []
        local_uvs: list[str] = []
        vertex_map: dict[int, int] = {}
        uv_map: dict[int, int] = {}
        face_lines: list[str] = []
        triangles = 0
        for material_name in batch:
            face_lines.append("usemtl " + material_name)
            for v_indices, uv_indices in faces_by_material[material_name]:
                pairs: list[str] = []
                for old_v, old_uv in zip(v_indices, uv_indices):
                    if old_v not in vertex_map:
                        vertex_map[old_v] = len(local_vertices) + 1
                        local_vertices.append(vertices[old_v - 1])
                    if old_uv not in uv_map:
                        uv_map[old_uv] = len(local_uvs) + 1
                        local_uvs.append(uvs[old_uv - 1])
                    pairs.append(f"{vertex_map[old_v]}/{uv_map[old_uv]}")
                face_lines.append("f " + " ".join(pairs))
                triangles += 1
        with part_obj.open("w", encoding="utf-8", newline="\n") as out:
            out.write(f"mtllib {part_mtl.name}\no {stem}\n")
            out.writelines(line + "\n" for line in local_vertices)
            out.writelines(line + "\n" for line in local_uvs)
            out.writelines(line + "\n" for line in face_lines)
        material_blocks: list[str] = []
        for material_name in batch:
            block = materials.get(material_name, ["newmtl " + material_name, "Kd 1.0 1.0 1.0"])
            material_blocks.append("\n".join(block))
        with part_mtl.open("w", encoding="utf-8", newline="\n") as out:
            out.write("\n\n".join(material_blocks) + "\n")
        part_files.append(part_obj.name)
        part_summaries.append({"file": part_obj.name, "materials": len(batch), "triangles": triangles, "vertices": len(local_vertices)})

    return {
        "tile": tile_name.replace("_", "/", 1),
        "source_obj": obj_path.name,
        "parts": part_files,
        "material_count": len(used_materials),
        "triangle_count": face_count,
        "excluded_triangle_count": excluded_face_count,
        "excluded_material_count": len(seen_excluded_materials),
        "part_summaries": part_summaries,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Directory containing the converted tile OBJ/MTL files")
    parser.add_argument("--output", type=Path, required=True, help="Directory for split Godot-ready OBJ/MTL parts")
    parser.add_argument("--material-limit", type=int, default=96, help="Maximum materials per imported OBJ; keep below Godot's 256-surface limit")
    parser.add_argument("--model-filter", type=Path, help="JSON list of tree/pole models and tree surface material keywords to remove")
    args = parser.parse_args()
    if args.material_limit < 1 or args.material_limit >= 256:
        parser.error("--material-limit must be between 1 and 255")
    model_filter = load_model_filter(args.model_filter)
    records = []
    for obj_path in sorted(args.source.glob("*.obj")):
        if "__part_" in obj_path.stem:
            continue
        record = split_tile(obj_path, args.output, obj_path.stem, args.material_limit, model_filter)
        records.append(record)
        print(json.dumps({"tile": record["tile"], "parts": len(record["parts"]), "materials": record["material_count"], "triangles": record["triangle_count"], "removed_triangles": record["excluded_triangle_count"]}), flush=True)
    manifest = {"schema": 1, "material_limit": args.material_limit, "tile_count": len(records), "tiles": records}
    args.output.mkdir(parents=True, exist_ok=True)
    runtime_root = args.output.parent
    texture_source = args.source.parent / "textures"
    texture_destination = runtime_root / "textures"
    copied_textures: set[str] = set()
    for mtl_path in sorted(args.output.glob("*.mtl")):
        for raw in mtl_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if not raw.startswith("map_Kd ../textures/"):
                continue
            relative = raw[len("map_Kd ../textures/"):]
            if relative in copied_textures:
                continue
            source_texture = texture_source / relative
            if not source_texture.is_file():
                raise FileNotFoundError(f"Texture referenced by {mtl_path} is missing: {source_texture}")
            destination_texture = texture_destination / relative
            destination_texture.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_texture, destination_texture)
            copied_textures.add(relative)
    catalog_source = args.source.parent / "gta3_tile_catalog.json"
    if catalog_source.is_file():
        shutil.copy2(catalog_source, runtime_root / catalog_source.name)
    manifest_path = args.output / "tile_parts.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": str(manifest_path), "tiles": len(records), "parts": sum(len(row["parts"]) for row in records), "textures": len(copied_textures), "removed_triangles": sum(row["excluded_triangle_count"] for row in records), "runtime_root": str(runtime_root)}))


if __name__ == "__main__":
    main()
