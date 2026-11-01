"""Generate a donor GLB of GORECE IFP reactions without replacing the active model.

Source ownership is intentionally separate from Andre:
- assets/source/gore/gore.dff + gore.txd: GORECE model and textures
- assets/source/gore/ped.ifp: GORECE locomotion, crouch, jump and fight choreography
- assets/source/ped.ifp: known-good arm rotations used to correct GORECE's FightA clips
- assets/source/gore/fight_e.ifp: special kick and hit reaction clips

Run with Blender and INU Tools:
  INU_TOOLS_PATH=/path/to/INU_Tools-GTA-Blender blender -b --python tools/convert_gore_ifp.py
"""
from pathlib import Path
import os
import sys
import bpy

PROJECT_ROOT = Path(__file__).resolve().parents[1]
INU_TOOLS_PATH = os.environ.get("INU_TOOLS_PATH", "/tmp/INU_Tools-GTA-Blender")
if INU_TOOLS_PATH not in sys.path:
    sys.path.insert(0, INU_TOOLS_PATH)

import INU_tools  # noqa: E402
INU_tools.register()
from INU_tools.ops.dff_import import import_dff  # noqa: E402
from INU_tools.ops.txd_import import import_txd  # noqa: E402
from INU_tools.ops.ifp_import import import_ifp, apply_ifp_action  # noqa: E402

SOURCE = PROJECT_ROOT / "assets/source/gore"
STANDARD_PED_SOURCE = PROJECT_ROOT / "assets/source/ped.ifp"
# Keep the source separate: the final Gorece GLB has hand-corrected FightA
# animations, so only the newly imported hit reactions should be merged into it.
OUT = PROJECT_ROOT / "assets/models/gorece_ifp_reaction_source.glb"

# These are deliberately selected from the two supplied IFP packages.
PED_ACTIONS = [
    "IDLE_stance", "WALK_civi", "run_civi", "Player_Sneak", "Player_Sneak_walkstart",
    "WEAPON_crouch", "JUMP_launch", "JUMP_glide", "JUMP_land", "FALL_fall", "FALL_land",
    "IDLE_armed", "WALK_armed", "run_armed",
    "FightA_block", "HIT_front", "HIT_back", "HIT_L", "HIT_R", "HitA_1", "HitA_2", "HitA_3",
]
BASE_COMBAT_ACTIONS = ["FightA_1", "FightA_2", "FightA_3"]
COMBAT_ACTIONS = ["FightKick", "FightKick_B", "Hit_fightkick", "Hit_fightkick_B"]
ROOT_MOTION_ACTIONS = set(PED_ACTIONS + COMBAT_ACTIONS)

# Start from a clean scene.
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.armatures, bpy.data.meshes, bpy.data.materials, bpy.data.actions):
    # Keep Blender's datablock cleanup conservative; imported data is replaced in this process.
    pass

print("IMPORT TXD", SOURCE / "gore.txd")
import_txd(str(SOURCE / "gore.txd"), assign_to_materials=False)
print("IMPORT DFF", SOURCE / "gore.dff")
import_dff(str(SOURCE / "gore.dff"), context=bpy.context, skip_2dfx=True)
armature = next((obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"), None)
if armature is None:
    raise RuntimeError("GORECE DFF did not create an armature")

print("IMPORT PED IFP", SOURCE / "ped.ifp")
ped_actions = import_ifp(str(SOURCE / "ped.ifp"), context=bpy.context)
print("PED ACTIONS", len(ped_actions))
# Preserve GORECE's own FightA choreography and duration. The source set has an
# extreme arm arc in some clips, so we'll correct only arm rotations from the
# known-good Andre IFP after both action sets have been applied to this rig.
gorece_fight_actions = {}
for action_name in BASE_COMBAT_ACTIONS:
    gore_action = bpy.data.actions.get(action_name)
    if gore_action is None:
        raise RuntimeError(f"GORECE IFP is missing {action_name}")
    ok, message = apply_ifp_action(action_name, armature, bpy.context)
    if not ok:
        raise RuntimeError(f"Could not apply GORECE {action_name}: {message}")
    gore_action.name = f"GORECE_SOURCE_{action_name}"
    gorece_fight_actions[action_name] = gore_action
print("IMPORT STANDARD PED IFP", STANDARD_PED_SOURCE)
standard_actions = import_ifp(str(STANDARD_PED_SOURCE), context=bpy.context)
print("STANDARD PED ACTIONS", len(standard_actions))
reference_fight_actions = {}
for action_name in BASE_COMBAT_ACTIONS:
    reference_action = bpy.data.actions.get(action_name)
    if reference_action is None:
        raise RuntimeError(f"Standard Andre IFP is missing {action_name}")
    ok, message = apply_ifp_action(action_name, armature, bpy.context)
    if not ok:
        raise RuntimeError(f"Could not apply standard {action_name}: {message}")
    reference_action.name = f"ANDRE_REFERENCE_{action_name}"
    reference_fight_actions[action_name] = reference_action

def _is_arm_bone(bone_name):
    name = bone_name.strip()
    has_side = name.startswith(("L ", "R ", "Bip01 L ", "Bip01 R "))
    return has_side and any(token in name for token in ("Clavicle", "UpperArm", "ForeArm", "Hand", "Finger"))

def _copy_reference_arm_rotations(source_action, target_action, armature):
    source_range = source_action.frame_range
    target_range = target_action.frame_range
    modified_bones = 0
    for pose_bone in armature.pose.bones:
        if not _is_arm_bone(pose_bone.name):
            continue
        data_path = f'pose.bones["{pose_bone.name}"].rotation_quaternion'
        source_curves = {fc.array_index: fc for fc in source_action.fcurves if fc.data_path == data_path}
        target_curves = [fc for fc in target_action.fcurves if fc.data_path == data_path]
        if len(source_curves) != 4 or len(target_curves) != 4:
            continue
        frames = sorted({float(point.co.x) for curve in target_curves for point in curve.keyframe_points})
        if not frames or target_range[1] <= target_range[0]:
            continue
        sampled = []
        for frame in frames:
            t = (frame - target_range[0]) / (target_range[1] - target_range[0])
            source_frame = source_range[0] + t * (source_range[1] - source_range[0])
            quat = [source_curves[index].evaluate(source_frame) for index in range(4)]
            magnitude = sum(value * value for value in quat) ** 0.5
            if magnitude > 1e-8:
                quat = [value / magnitude for value in quat]
            sampled.append((frame, quat))
        for curve in target_curves:
            target_action.fcurves.remove(curve)
        for component in range(4):
            curve = target_action.fcurves.new(data_path=data_path, index=component)
            for frame, quat in sampled:
                point = curve.keyframe_points.insert(frame, quat[component], options={"FAST"})
                point.interpolation = "LINEAR"
            curve.update()
        modified_bones += 1
    return modified_bones

for action_name in BASE_COMBAT_ACTIONS:
    target_action = gorece_fight_actions[action_name]
    reference_action = reference_fight_actions[action_name]
    changed = _copy_reference_arm_rotations(reference_action, target_action, armature)
    if changed < 8:
        raise RuntimeError(f"Only {changed} arm bones were corrected in {action_name}")
    print(
        f"CORRECTED ARM ROTATIONS {action_name}: bones={changed} "
        f"kept GORECE frames={tuple(target_action.frame_range)}"
    )
    bpy.data.actions.remove(reference_action, do_unlink=True)
    target_action.name = action_name

print("IMPORT FIGHT_E IFP", SOURCE / "fight_e.ifp")
fight_actions = import_ifp(str(SOURCE / "fight_e.ifp"), context=bpy.context)
print("FIGHT_E ACTIONS", len(fight_actions))

available = {action.name for action in bpy.data.actions}
selected = []
for action_name in PED_ACTIONS + BASE_COMBAT_ACTIONS + COMBAT_ACTIONS:
    if action_name not in available:
        print("SKIP MISSING ACTION", action_name)
        continue
    ok, message = apply_ifp_action(action_name, armature, bpy.context)
    print("APPLY", action_name, ok, message)
    if not ok:
        raise RuntimeError(f"Could not apply {action_name}: {message}")
    selected.append(action_name)

# CharacterBody3D owns translation; remove root motion from actions so the model does not teleport.
for action_name in selected:
    action = bpy.data.actions.get(action_name)
    if action is None:
        continue
    for fcurve in list(action.fcurves):
        if fcurve.data_path == 'pose.bones["Root"].location':
            # CharacterBody3D owns world movement, but crouch depth can live in
            # the root's vertical curve. Keep that Y curve for the sneak clips.
            preserve_crouch_height = action_name in {"Player_Sneak", "Player_Sneak_walkstart", "WEAPON_crouch"} and fcurve.array_index == 1
            if not preserve_crouch_height:
                action.fcurves.remove(fcurve)
    print("REMOVED ROOT MOTION", action_name)

bpy.context.scene.render.fps = 30
bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type in {"ARMATURE", "MESH"}:
        obj.select_set(True)
        obj.hide_viewport = False
        obj.hide_render = False
bpy.context.view_layer.objects.active = armature
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUT),
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_skins=True,
    export_def_bones=True,
    export_all_influences=True,
    export_materials="EXPORT",
    export_image_format="AUTO",
)
if not OUT.is_file() or OUT.stat().st_size < 100_000:
    raise RuntimeError(f"GLB export missing or unexpectedly small: {OUT}")
print("EXPORTED", OUT, OUT.stat().st_size, "bytes")
print("ANIMATIONS", selected)
bpy.ops.wm.quit_blender()
