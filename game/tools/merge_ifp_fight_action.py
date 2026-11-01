"""Add FightA_1/2/3 from andre_rigged.glb to the existing armed character GLB.

Run after convert_dff_ifp.py with:
    blender -b --python tools/merge_ifp_fight_action.py

The merge is guarded by a matching bone-name/rest-pose check and exports to a
staging file before replacing andre_armed.glb.
"""

import json
import os
import struct
from pathlib import Path

import bpy

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARMED_GLB = PROJECT_ROOT / "assets/models/andre_armed.glb"
IFP_GLB = PROJECT_ROOT / "assets/models/andre_rigged.glb"
STAGING_GLB = PROJECT_ROOT / "assets/models/andre_armed.with_ifp_staging.glb"

FIGHT_ACTIONS = ("FightA_1", "FightA_2", "FightA_3")

if not ARMED_GLB.is_file():
    raise FileNotFoundError(f"Armed model not found: {ARMED_GLB}")
if not IFP_GLB.is_file():
    raise FileNotFoundError(f"Converted IFP model not found: {IFP_GLB}; run convert_dff_ifp.py first")

# Start from a clean scene, then import the game model whose animations/materials
# must be preserved.
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
base_objects_before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(ARMED_GLB))
base_objects = set(bpy.data.objects) - base_objects_before
base_armature = next((obj for obj in base_objects if obj.type == "ARMATURE"), None)
if base_armature is None:
    raise RuntimeError("andre_armed.glb did not import an armature")
base_actions = set(bpy.data.actions)

# Drop any pre-existing fight clips from the armed model so the export has
# exactly one of each FightA_n from the IFP source.
for action in list(bpy.data.actions):
    if action.name == "FightA_1" or action.name.startswith("FightA_"):
        print(f"REMOVE EXISTING {action.name}")
        bpy.data.actions.remove(action)
base_actions = set(bpy.data.actions)

# Import the converted IFP model and locate the source actions and its armature.
source_objects_before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(IFP_GLB))
source_objects = set(bpy.data.objects) - source_objects_before
source_actions = set(bpy.data.actions) - base_actions
source_armature = next((obj for obj in source_objects if obj.type == "ARMATURE"), None)
if source_armature is None:
    raise RuntimeError("andre_rigged.glb did not import an armature")

base_bones = {bone.name: bone for bone in base_armature.data.bones}
source_bones = {bone.name: bone for bone in source_armature.data.bones}
if base_bones.keys() != source_bones.keys():
    missing = sorted(base_bones.keys() - source_bones.keys())
    extra = sorted(source_bones.keys() - base_bones.keys())
    raise RuntimeError(f"IFP rig does not match the game model (missing={missing}, extra={extra})")

max_rest_delta = 0.0
for bone_name, base_bone in base_bones.items():
    source_bone = source_bones[bone_name]
    for row in range(4):
        for column in range(4):
            max_rest_delta = max(
                max_rest_delta,
                abs(base_bone.matrix_local[row][column] - source_bone.matrix_local[row][column]),
            )
if max_rest_delta > 1e-3:
    raise RuntimeError(f"IFP rig rest pose differs from the game model (max delta={max_rest_delta:.6f})")

# Match source actions by name prefix (gltf export may append suffixes).
copied_actions = []
for fight_name in FIGHT_ACTIONS:
    source_action = next(
        (
            action
            for action in source_actions
            if action.name == fight_name or action.name.startswith(fight_name + "_")
        ),
        None,
    )
    if source_action is None:
        available = sorted(a.name for a in source_actions)
        raise RuntimeError(f"{fight_name} not found in IFP GLB; imported actions: {available}")

    # Drop any existing same-named action on the base model so the export is clean.
    existing = bpy.data.actions.get(fight_name)
    if existing is not None and existing not in source_actions:
        bpy.data.actions.remove(existing)

    fight_action = source_action.copy()
    fight_action.name = fight_name
    copied_actions.append(fight_action)
    print(
        f"MERGE {fight_name} frames={tuple(source_action.frame_range)} "
        f"curves={len(source_action.fcurves)} bones={len(base_bones)} "
        f"rest_delta={max_rest_delta:.8f}"
    )

# Assign the first fight clip so the armature has animation_data for export.
base_armature.animation_data_create()
base_armature.animation_data.action = copied_actions[0]

# Remove the temporary source rig and its duplicate actions; retain the original
# animations from andre_armed.glb plus the copied fight actions.
for obj in source_objects:
    bpy.data.objects.remove(obj, do_unlink=True)
for action in list(source_actions):
    if action not in copied_actions:
        bpy.data.actions.remove(action)

bpy.ops.object.select_all(action="DESELECT")
for obj in base_objects:
    if obj.type in {"ARMATURE", "MESH"}:
        obj.select_set(True)
bpy.context.view_layer.objects.active = base_armature

if STAGING_GLB.exists():
    STAGING_GLB.unlink()
bpy.ops.export_scene.gltf(
    filepath=str(STAGING_GLB),
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_skins=True,
    export_def_bones=True,
    export_all_influences=True,
    export_materials="EXPORT",
)
if not STAGING_GLB.is_file() or STAGING_GLB.stat().st_size < 100_000:
    raise RuntimeError("GLB export did not produce a complete staging model")

# Validate the generated GLB before replacing the game asset.
data = STAGING_GLB.read_bytes()
if data[:4] != b"glTF":
    raise RuntimeError("Staging file is not a binary glTF")
json_length, json_type = struct.unpack_from("<II", data, 12)
if json_type != 0x4E4F534A:
    raise RuntimeError("Staging GLB has no JSON chunk")
gltf = json.loads(data[20 : 20 + json_length])
animation_names = {animation.get("name") for animation in gltf.get("animations", [])}
missing = [name for name in FIGHT_ACTIONS if name not in animation_names]
if missing:
    raise RuntimeError(f"Fight clips absent from exported GLB: {missing}; have {sorted(animation_names)}")

os.replace(STAGING_GLB, ARMED_GLB)
print(f"UPDATED {ARMED_GLB} with {list(FIGHT_ACTIONS)}")
print(f"ANIMATIONS {sorted(animation_names)}")
