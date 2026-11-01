#!/usr/bin/env python3
"""Extract GTA III IMG v1 payloads using the companion .dir index.

The supplied mobile archive uses 2048-byte sectors and a 32-byte DIR record:
uint32 sector offset, uint32 sector count, 24-byte NUL-padded filename.
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

SECTOR = 2048
RECORD = 32


def extract(img_path: Path, dir_path: Path, out_dir: Path) -> dict:
    img_size = img_path.stat().st_size
    directory = dir_path.read_bytes()
    if len(directory) % RECORD:
        raise ValueError(f"DIR size is not a multiple of {RECORD}: {len(directory)}")
    out_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    seen: dict[str, int] = {}
    with img_path.open("rb") as img:
        for index in range(len(directory) // RECORD):
            sector, count = struct.unpack_from("<II", directory, index * RECORD)
            raw_name = directory[index * RECORD + 8 : index * RECORD + RECORD]
            name = raw_name.split(b"\0", 1)[0].decode("ascii", "replace").strip()
            if not name:
                continue
            safe_name = Path(name).name
            if safe_name in seen:
                seen[safe_name] += 1
                stem = Path(safe_name).stem
                suffix = Path(safe_name).suffix
                safe_name = f"{stem}__duplicate_{seen[Path(name).name]}{suffix}"
            else:
                seen[safe_name] = 0
            byte_offset = sector * SECTOR
            byte_length = count * SECTOR
            if byte_offset + byte_length > img_size:
                raise ValueError(
                    f"Entry {name} exceeds IMG: offset={byte_offset}, size={byte_length}, img={img_size}"
                )
            img.seek(byte_offset)
            payload = img.read(byte_length)
            # IMG records are sector-padded. RenderWare chunks carry their own exact size;
            # preserving the padded bytes is intentional and keeps the extraction lossless.
            target = out_dir / safe_name
            target.write_bytes(payload)
            entries.append({
                "index": index,
                "name": name,
                "output": safe_name,
                "sector": sector,
                "sectors": count,
                "bytes_padded": byte_length,
            })
    manifest = {
        "img": str(img_path),
        "dir": str(dir_path),
        "sector_size": SECTOR,
        "entry_count": len(entries),
        "entries": entries,
    }
    (out_dir / "img_extract_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("img", type=Path)
    parser.add_argument("dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = extract(args.img, args.dir, args.output)
    counts: dict[str, int] = {}
    for entry in manifest["entries"]:
        suffix = Path(entry["name"]).suffix.lower() or "<none>"
        counts[suffix] = counts.get(suffix, 0) + 1
    print(json.dumps({"entry_count": manifest["entry_count"], "by_extension": counts}, indent=2))


if __name__ == "__main__":
    main()
