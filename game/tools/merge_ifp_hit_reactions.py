"""Merge Andre's directional hit reactions into the GLB used by the game scene.

Run after convert_dff_ifp.py:
    blender -b --python tools/merge_ifp_hit_reactions.py

The script validates the source/destination rig, exports to a staging file, checks
that every requested animation was preserved, and only then replaces the model.
"""
import json
import struct
from pathlib import Path
import bpy

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TARGET_GLB = PROJECT_ROOT / "assets/models/andre_armed_biked.glb"
SOURCE_GLB = PROJECT_ROOT / "assets/models/andre_rigged.glb"
STAGING_GLB = PROJECT_ROOT / "assets/models/andre_armed_biked.hit_staging.glb"
HIT_ACTIONS = ("HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3")

if not TARGET_GLB.is_file():
    raise FileNotFoundError(f"Scene character model not found: {TARGET_GLB}")
if not SOURCE_GLB.is_file():
    raise FileNotFoundError(f"Converted IFP model not found: {SOURCE_GLB}; run convert_dff_ifp.py first")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
base_actions_before = set(bpy.data.actions)
target_objects_before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(TARGET_GLB))
target_objects = set(bpy.data.objects) - target_objects_before
target_armature = next((obj for obj in target_objects if obj.type == "ARMATURE"), None)
if target_armature is None:
    raise RuntimeError("andre_armed_biked.glb did not import an armature")

for action in list(bpy.data.actions):
    if action.name in HIT_ACTIONS:
        bpy.data.actions.remove(action)
target_actions = set(bpy.data.actions) - base_actions_before
source_objects_before = set(bpy.data.objects)
source_actions_before = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=str(SOURCE_GLB))
source_objects = set(bpy.data.objects) - source_objects_before
source_actions = set(bpy.data.actions) - source_actions_before
source_armature = next((obj for obj in source_objects if obj.type == "ARMATURE"), None)
if source_armature is None:
    raise RuntimeError("andre_rigged.glb did not import an armature")

base_bones = {bone.name: bone for bone in target_armature.data.bones}
source_bones = {bone.name: bone for bone in source_armature.data.bones}
if base_bones.keys() != source_bones.keys():
    missing = sorted(base_bones.keys() - source_bones.keys())
    extra = sorted(source_bones.keys() - base_bones.keys())
    raise RuntimeError(f"IFP rig does not match the scene model (missing={missing}, extra={extra})")
max_rest_delta = 0.0
for bone_name, base_bone in base_bones.items():
    source_bone = source_bones[bone_name]
    for row in range(4):
        for column in range(4):
            max_rest_delta = max(max_rest_delta, abs(base_bone.matrix_local[row][column] - source_bone.matrix_local[row][column]))
if max_rest_delta > 1e-3:
    raise RuntimeError(f"IFP rig rest pose differs from andre_armed_biked.glb (max delta={max_rest_delta:.6f})")

copied_actions = []
for animation_name in HIT_ACTIONS:
    source_action = next((action for action in source_actions if action.name == animation_name or action.name.startswith(animation_name + "_")), None)
    if source_action is None:
        raise RuntimeError(f"{animation_name} not found in converted IFP GLB; found {sorted(a.name for a in source_actions)}")
    duplicate = source_action.copy()
    duplicate.name = animation_name
    copied_actions.append(duplicate)
    print(f"MERGE {animation_name}: frames={tuple(source_action.frame_range)} curves={len(source_action.fcurves)}")

target_armature.animation_data_create()
target_armature.animation_data.action = copied_actions[0]
for obj in source_objects:
    bpy.data.objects.remove(obj, do_unlink=True)
for action in list(source_actions):
    if action not in copied_actions:
        bpy.data.actions.remove(action)

bpy.ops.object.select_all(action="DESELECT")
for obj in target_objects:
    if obj.type in {"ARMATURE", "MESH"}:
        obj.select_set(True)
        obj.hide_viewport = False
        obj.hide_render = False
bpy.context.view_layer.objects.active = target_armature
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
data = STAGING_GLB.read_bytes()
if data[:4] != b"glTF":
    raise RuntimeError("Staging file is not a GLB")
json_length = struct.unpack_from("<I", data, 12)[0]
gltf = json.loads(data[20:20 + json_length])
exported_names = {animation.get("name", "") for animation in gltf.get("animations", [])}
missing = sorted(set(HIT_ACTIONS) - exported_names)
if missing:
    raise RuntimeError(f"Staging GLB is missing hit reactions: {missing}")
STAGING_GLB.replace(TARGET_GLB)
print(f"UPDATED {TARGET_GLB} with {len(HIT_ACTIONS)} hit reactions")
