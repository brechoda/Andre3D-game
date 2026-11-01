#!/usr/bin/env python3
"""Build a compact tile catalog from the GTA III placement manifest."""
from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path


def tile_name(source: str) -> str:
    source = source.replace("\\", "/")
    parts = [p for p in source.split("/") if p]
    if len(parts) >= 2 and parts[-1].lower().endswith(".ipl"):
        return parts[-2].lower() + "/" + Path(parts[-1]).stem.lower()
    return Path(parts[-1] if parts else "unknown").stem.lower()


def build(manifest_path: Path) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    groups: dict[str, list[dict]] = defaultdict(list)
    for placement in manifest.get("placements", []):
        groups[tile_name(str(placement.get("source", "unknown.ipl")))].append(placement)

    tiles = []
    for name in sorted(groups):
        placements = groups[name]
        xs = [float(p["position"][0]) for p in placements]
        ys = [float(p["position"][1]) for p in placements]
        zs = [float(p["position"][2]) for p in placements]
        models = sorted({str(p.get("model", "")) for p in placements})
        txds = sorted({str(p.get("txd", "")) for p in placements if p.get("txd")})
        tiles.append({
            "name": name,
            "placement_count": len(placements),
            "model_count": len(models),
            "texture_dictionary_count": len(txds),
            "bounds_min": [min(xs), min(ys), min(zs)],
            "bounds_max": [max(xs), max(ys), max(zs)],
            "center": [(min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2],
            "radius": math.sqrt((max(xs) - min(xs)) ** 2 + (max(ys) - min(ys)) ** 2) / 2,
            "models": models,
            "texture_dictionaries": txds,
        })
    return {
        "schema": 1,
        "source_manifest": str(manifest_path),
        "placement_count": len(manifest.get("placements", [])),
        "tile_count": len(tiles),
        "tiles": tiles,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    catalog = build(args.manifest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: catalog[k] for k in ("placement_count", "tile_count")}, indent=2))
    for tile in catalog["tiles"]:
        print(f"{tile['name']}: {tile['placement_count']} placements, {tile['model_count']} models")


if __name__ == "__main__":
    main()
