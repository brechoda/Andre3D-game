"""Convert the supplied DG DFF skin to a Godot GLB with Andre's full animation set.

Requirements: Blender + the INU Tools GTA Blender addon.
Run from any directory:
    INU_TOOLS_PATH=/path/to/INU_Tools-GTA-Blender blender -b --python tools/convert_dg_skin.py
"""
from __future__ import annotations

import json
import os
import struct
import sys
from pathlib import Path

import bpy

PROJECT_ROOT = Path(__file__).resolve().parents[1]
INU_TOOLS_PATH = os.environ.get("INU_TOOLS_PATH", "/tmp/INU_Tools-GTA-Blender")
SOURCE_DIR = PROJECT_ROOT / "assets/source/skin_dg"
DFF_PATH = SOURCE_DIR / "dg.dff"
ANDRE_GLB = PROJECT_ROOT / "assets/models/andre_armed_biked.glb"
OUTPUT_GLB = PROJECT_ROOT / "assets/models/dg_rigged.glb"

if INU_TOOLS_PATH not in sys.path:
    sys.path.insert(0, INU_TOOLS_PATH)

import INU_tools  # noqa: E402

INU_tools.register()
from INU_tools.ops.dff_import import import_dff  # noqa: E402


def _read_glb_animation_names(path: Path) -> list[str]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise RuntimeError(f"Not a GLB file: {path}")
    json_size = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20 : 20 + json_size])
    return [str(animation["name"]) for animation in document.get("animations", [])]


def _find_image_for_material(material_name: str, texture_paths: dict[str, Path]) -> Path | None:
    base_name = material_name.rsplit(".", 1)[0].strip().casefold()
    return texture_paths.get(base_name)


def _assign_supplied_textures(meshes: list[bpy.types.Object]) -> None:
    texture_paths = {
        path.stem.strip().casefold(): path
        for path in SOURCE_DIR.glob("*.png")
    }
    if not texture_paths:
        raise RuntimeError(f"No supplied PNG textures found next to {DFF_PATH}")

    assigned: set[str] = set()
    for mesh_obj in meshes:
        for material in mesh_obj.data.materials:
            if material is None:
                continue
            image_path = _find_image_for_material(material.name, texture_paths)
            if image_path is None:
                raise RuntimeError(
                    f"No supplied PNG matches DFF material {material.name!r}; "
                    f"available={sorted(texture_paths)}"
                )
            material.use_nodes = True
            nodes = material.node_tree.nodes
            principled = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
            if principled is None:
                principled = nodes.new("ShaderNodeBsdfPrincipled")
            image_node = next((node for node in nodes if node.type == "TEX_IMAGE"), None)
            if image_node is None:
                image_node = nodes.new("ShaderNodeTexImage")
            image_node.image = bpy.data.images.load(str(image_path), check_existing=True)
            image_node.interpolation = "Linear"
            image_node.label = image_path.name
            material.node_tree.links.new(image_node.outputs["Color"], principled.inputs["Base Color"])
            alpha_input = principled.inputs.get("Alpha")
            if alpha_input is not None:
                material.node_tree.links.new(image_node.outputs["Alpha"], alpha_input)
            material.diffuse_color = (1.0, 1.0, 1.0, 1.0)
            assigned.add(material.name)
    print("TEXTURES", sorted(assigned))


def _set_export_selection(objects: list[bpy.types.Object], active: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        if obj.type in {"ARMATURE", "MESH"}:
            obj.select_set(True)
            obj.hide_viewport = False
            obj.hide_render = False
    bpy.context.view_layer.objects.active = active


def main() -> None:
    if not DFF_PATH.is_file():
        raise FileNotFoundError(DFF_PATH)
    if not ANDRE_GLB.is_file():
        raise FileNotFoundError(ANDRE_GLB)
    expected_animations = _read_glb_animation_names(ANDRE_GLB)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    print("IMPORT DFF", DFF_PATH)
    before_skin = set(bpy.data.objects)
    import_dff(str(DFF_PATH), context=bpy.context, skip_2dfx=True)
    skin_objects = set(bpy.data.objects) - before_skin
    skin_armature = next((obj for obj in skin_objects if obj.type == "ARMATURE"), None)
    skin_meshes = [obj for obj in skin_objects if obj.type == "MESH"]
    if skin_armature is None or not skin_meshes:
        raise RuntimeError("The supplied DFF did not produce both a rig and skinned meshes")
    _assign_supplied_textures(skin_meshes)

    print("IMPORT ANDRE ANIMATIONS", ANDRE_GLB)
    before_andre = set(bpy.data.objects)
    actions_before_andre = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(ANDRE_GLB))
    andre_objects = set(bpy.data.objects) - before_andre
    andre_armature = next((obj for obj in andre_objects if obj.type == "ARMATURE"), None)
    if andre_armature is None or andre_armature.animation_data is None:
        raise RuntimeError("Andre GLB is missing its rig or animation tracks")

    dg_bones = {bone.name: bone for bone in skin_armature.data.bones}
    andre_bones = {bone.name: bone for bone in andre_armature.data.bones}
    if dg_bones.keys() != andre_bones.keys():
        raise RuntimeError(
            "DG rig does not match Andre's skeleton: "
            f"missing={sorted(andre_bones.keys() - dg_bones.keys())}, "
            f"extra={sorted(dg_bones.keys() - andre_bones.keys())}"
        )
    rest_delta = max(
        abs(dg_bones[name].matrix_local[row][column] - andre_bones[name].matrix_local[row][column])
        for name in dg_bones
        for row in range(4)
        for column in range(4)
    )
    print("RIG", len(dg_bones), "bones; max rest-pose delta", rest_delta)
    if rest_delta > 0.01:
        raise RuntimeError(f"DG skeleton rest pose differs too much from Andre: {rest_delta:.6f}")

    if skin_armature.animation_data is None:
        skin_armature.animation_data_create()

    # The Andre GLB imported as one NLA track per game animation. Copy every
    # animation datablock to the identical named DG bones and create matching
    # NLA tracks so Godot sees the same clip names at runtime.
    copied_names: list[str] = []
    for source_track in andre_armature.animation_data.nla_tracks:
        if not source_track.strips:
            continue
        source_strip = source_track.strips[0]
        source_action = source_strip.action
        if source_action is None:
            continue
        clip_name = source_track.name
        if clip_name not in expected_animations:
            continue
        action_copy = source_action.copy()
        action_copy.name = clip_name
        target_track = skin_armature.animation_data.nla_tracks.new()
        target_track.name = clip_name
        target_strip = target_track.strips.new(clip_name, 1, action_copy)
        target_strip.action_frame_start = source_strip.action_frame_start
        target_strip.action_frame_end = source_strip.action_frame_end
        target_strip.frame_start = 1
        target_strip.scale = source_strip.scale
        target_track.mute = False
        copied_names.append(clip_name)

    missing_animations = sorted(set(expected_animations) - set(copied_names))
    if missing_animations:
        raise RuntimeError(f"Could not copy all Andre animations: {missing_animations}")
    if len(copied_names) != len(set(copied_names)):
        raise RuntimeError("Andre GLB has duplicate animation track names")
    print("COPIED ANIMATIONS", len(copied_names), sorted(copied_names))

    # Remove Andre's temporary geometry/rig; the copied NLA actions now target
    # the DG rig exclusively.
    for obj in andre_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(set(bpy.data.actions) - actions_before_andre):
        if action.users == 0:
            bpy.data.actions.remove(action)

    skin_armature.name = "DG_Armature"
    for mesh_obj in skin_meshes:
        mesh_obj.name = "DG_Character"
        mesh_obj.parent = skin_armature
        for modifier in mesh_obj.modifiers:
            if modifier.type == "ARMATURE":
                modifier.object = skin_armature

    _set_export_selection(list(skin_objects), skin_armature)
    OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT_GLB.exists():
        OUTPUT_GLB.unlink()
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_skins=True,
        export_def_bones=True,
        export_all_influences=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    actual_animations = _read_glb_animation_names(OUTPUT_GLB)
    if set(actual_animations) != set(expected_animations):
        raise RuntimeError(
            "Exported GLB animation list differs from Andre: "
            f"missing={sorted(set(expected_animations) - set(actual_animations))}, "
            f"extra={sorted(set(actual_animations) - set(expected_animations))}"
        )
    if OUTPUT_GLB.stat().st_size < 100_000:
        raise RuntimeError(f"Exported GLB is unexpectedly small: {OUTPUT_GLB.stat().st_size}")
    print("EXPORTED", OUTPUT_GLB, OUTPUT_GLB.stat().st_size, "bytes")
    print("ANIMATION CHECK PASS", len(actual_animations))


if __name__ == "__main__":
    main()
