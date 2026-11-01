"""Append only Gorece's IFP hit-reaction animations to the original GLB.

This is a raw glTF/GLB animation merge: it does not round-trip the original
mesh or animation tracks through Blender. That is intentional so the hand-tuned
FightA clips remain byte-for-byte unchanged.

Run after tools/convert_gore_ifp.py:
    python3 tools/merge_gorece_ifp_hit_reactions.py
"""
from __future__ import annotations

import copy
import json
import struct
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TARGET_GLB = PROJECT_ROOT / "assets/models/gorece_rigged.glb"
SOURCE_GLB = PROJECT_ROOT / "assets/models/gorece_ifp_reaction_source.glb"
STAGING_GLB = PROJECT_ROOT / "assets/models/gorece_rigged.rawmerge_staging.glb"
HIT_ACTIONS = ("HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3")
PRESERVE_ACTIONS = ("FightA_1", "FightA_2", "FightA_3", "FightKick", "FightKick_B")
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(path: Path) -> tuple[int, list[tuple[int, bytes]], dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise RuntimeError(f"Not a complete GLB: {path}")
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(data):
        raise RuntimeError(f"Invalid GLB header: {path}")
    chunks: list[tuple[int, bytes]] = []
    document = None
    binary = None
    offset = 12
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        payload_start = offset + 8
        payload = data[payload_start:payload_start + chunk_length]
        if len(payload) != chunk_length:
            raise RuntimeError(f"Truncated GLB chunk: {path}")
        chunks.append((chunk_type, payload))
        if chunk_type == JSON_CHUNK:
            document = json.loads(payload.rstrip(b" \t\r\n\0").decode("utf-8"))
        elif chunk_type == BIN_CHUNK:
            binary = payload
        offset = payload_start + chunk_length
    if document is None or binary is None:
        raise RuntimeError(f"GLB must contain JSON and BIN chunks: {path}")
    return version, chunks, document, binary


def encode_glb(version: int, chunks: list[tuple[int, bytes]]) -> bytes:
    body = bytearray()
    for chunk_type, payload in chunks:
        padding = (-len(payload)) % 4
        if padding:
            pad_byte = b" " if chunk_type == JSON_CHUNK else b"\0"
            payload = payload + pad_byte * padding
        body.extend(struct.pack("<II", len(payload), chunk_type))
        body.extend(payload)
    return struct.pack("<4sII", b"glTF", version, 12 + len(body)) + body


def unique_node_map(document: dict, label: str) -> dict[str, int]:
    mapping: dict[str, int] = {}
    for index, node in enumerate(document.get("nodes", [])):
        name = node.get("name")
        if not name:
            continue
        if name in mapping:
            raise RuntimeError(f"Duplicate node name {name!r} in {label}; safe animation remap is ambiguous")
        mapping[name] = index
    return mapping


def main() -> None:
    for path in (TARGET_GLB, SOURCE_GLB):
        if not path.is_file():
            raise FileNotFoundError(f"Required GLB is missing: {path}")

    base_version, base_chunks, base_doc, base_bin_chunk = read_glb(TARGET_GLB)
    _, _, source_doc, source_bin_chunk = read_glb(SOURCE_GLB)
    if len(base_doc.get("buffers", [])) != 1 or len(source_doc.get("buffers", [])) != 1:
        raise RuntimeError("Only single-buffer GLB assets are supported")
    base_binary_length = int(base_doc["buffers"][0]["byteLength"])
    source_binary_length = int(source_doc["buffers"][0]["byteLength"])
    if base_binary_length > len(base_bin_chunk) or source_binary_length > len(source_bin_chunk):
        raise RuntimeError("GLB buffer byteLength exceeds its BIN chunk")
    base_binary = bytearray(base_bin_chunk[:base_binary_length])
    source_binary = source_bin_chunk[:source_binary_length]

    base_nodes = unique_node_map(base_doc, "original Gorece GLB")
    source_nodes = unique_node_map(source_doc, "IFP reaction source GLB")
    source_animation_by_name = {animation.get("name", ""): animation for animation in source_doc.get("animations", [])}
    missing_source = sorted(set(HIT_ACTIONS) - source_animation_by_name.keys())
    if missing_source:
        raise RuntimeError(f"Reaction source is missing IFP clips: {missing_source}")

    # Guard that both assets describe the same skin joint set before binding
    # donor tracks to the original model's nodes.
    def joint_names(document: dict) -> set[str]:
        nodes = document.get("nodes", [])
        names: set[str] = set()
        for skin in document.get("skins", []):
            for node_index in skin.get("joints", []):
                name = nodes[node_index].get("name")
                if name:
                    names.add(name)
        return names

    base_joints = joint_names(base_doc)
    source_joints = joint_names(source_doc)
    if base_joints != source_joints:
        raise RuntimeError(
            "IFP reaction rig differs from original Gorece model "
            f"(missing={sorted(base_joints - source_joints)}, extra={sorted(source_joints - base_joints)})"
        )

    original_fight_json = {
        animation.get("name"): copy.deepcopy(animation)
        for animation in base_doc.get("animations", [])
        if animation.get("name") in PRESERVE_ACTIONS
    }
    missing_original = sorted(set(PRESERVE_ACTIONS) - original_fight_json.keys())
    if missing_original:
        raise RuntimeError(f"Original Gorece GLB is missing expected combat clips: {missing_original}")

    # Preserve existing source-independent assets and replace only same-named hit
    # clips if the tool is run more than once.
    base_doc["animations"] = [
        animation for animation in base_doc.get("animations", [])
        if animation.get("name") not in HIT_ACTIONS
    ]
    view_map: dict[int, int] = {}
    accessor_map: dict[int, int] = {}

    def copy_accessor(source_accessor_index: int) -> int:
        if source_accessor_index in accessor_map:
            return accessor_map[source_accessor_index]
        source_accessor = source_doc["accessors"][source_accessor_index]
        if "sparse" in source_accessor:
            raise RuntimeError("Sparse animation accessors are not supported by this merger")
        accessor = copy.deepcopy(source_accessor)
        if "bufferView" in accessor:
            source_view_index = accessor["bufferView"]
            if source_view_index not in view_map:
                source_view = copy.deepcopy(source_doc["bufferViews"][source_view_index])
                if source_view.get("buffer", 0) != 0:
                    raise RuntimeError("Animation accessor references a nonzero source buffer")
                source_start = int(source_view.get("byteOffset", 0))
                source_length = int(source_view["byteLength"])
                source_end = source_start + source_length
                if source_start < 0 or source_end > len(source_binary):
                    raise RuntimeError("Animation bufferView falls outside source BIN data")
                padding = (-len(base_binary)) % 4
                if padding:
                    base_binary.extend(b"\0" * padding)
                source_view["buffer"] = 0
                source_view["byteOffset"] = len(base_binary)
                copied_view_index = len(base_doc.setdefault("bufferViews", []))
                base_doc["bufferViews"].append(source_view)
                base_binary.extend(source_binary[source_start:source_end])
                view_map[source_view_index] = copied_view_index
            accessor["bufferView"] = view_map[source_accessor_index_view := source_accessor["bufferView"]]
        new_accessor_index = len(base_doc.setdefault("accessors", []))
        base_doc["accessors"].append(accessor)
        accessor_map[source_accessor_index] = new_accessor_index
        return new_accessor_index

    for animation_name in HIT_ACTIONS:
        animation = copy.deepcopy(source_animation_by_name[animation_name])
        for sampler in animation.get("samplers", []):
            sampler["input"] = copy_accessor(sampler["input"])
            sampler["output"] = copy_accessor(sampler["output"])
        for channel in animation.get("channels", []):
            source_node_index = channel["target"]["node"]
            source_node_name = source_doc["nodes"][source_node_index].get("name")
            if not source_node_name or source_node_name not in base_nodes:
                raise RuntimeError(f"Animation target node cannot be mapped: {source_node_name!r}")
            channel["target"]["node"] = base_nodes[source_node_name]
        base_doc["animations"].append(animation)

    # Verify the original fight animation JSON is untouched before serializing.
    final_animation_json = {
        animation.get("name"): animation
        for animation in base_doc.get("animations", [])
        if animation.get("name") in PRESERVE_ACTIONS
    }
    if final_animation_json != original_fight_json:
        raise RuntimeError("FightA/FightKick animation definitions changed during merge")

    base_doc["buffers"][0]["byteLength"] = len(base_binary)
    json_payload = json.dumps(base_doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    new_chunks: list[tuple[int, bytes]] = []
    json_added = False
    bin_added = False
    for chunk_type, payload in base_chunks:
        if chunk_type == JSON_CHUNK:
            new_chunks.append((JSON_CHUNK, json_payload))
            json_added = True
        elif chunk_type == BIN_CHUNK:
            new_chunks.append((BIN_CHUNK, bytes(base_binary)))
            bin_added = True
        else:
            new_chunks.append((chunk_type, payload))
    if not json_added or not bin_added:
        raise RuntimeError("Original GLB chunks could not be rebuilt")

    encoded = encode_glb(base_version, new_chunks)
    STAGING_GLB.write_bytes(encoded)
    _, _, verified_doc, verified_bin = read_glb(STAGING_GLB)
    verified_names = {animation.get("name", "") for animation in verified_doc.get("animations", [])}
    missing = sorted((set(HIT_ACTIONS) | set(PRESERVE_ACTIONS)) - verified_names)
    if missing:
        STAGING_GLB.unlink(missing_ok=True)
        raise RuntimeError(f"Staging GLB failed animation validation: missing {missing}")
    if verified_bin[:base_binary_length] != bytes(base_binary[:base_binary_length]):
        STAGING_GLB.unlink(missing_ok=True)
        raise RuntimeError("Original BIN prefix changed unexpectedly")
    verified_fight_json = {
        animation.get("name"): animation
        for animation in verified_doc.get("animations", [])
        if animation.get("name") in PRESERVE_ACTIONS
    }
    if verified_fight_json != original_fight_json:
        STAGING_GLB.unlink(missing_ok=True)
        raise RuntimeError("FightA/FightKick tracks were not preserved exactly")

    STAGING_GLB.replace(TARGET_GLB)
    print(
        f"UPDATED {TARGET_GLB}: added {len(HIT_ACTIONS)} IFP reactions; "
        f"FightA/FightKick JSON and original binary prefix preserved"
    )


if __name__ == "__main__":
    main()
