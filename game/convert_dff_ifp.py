import bpy
import os
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
addon_default = root.parent / 'inu-tools-gta-sa'
ADDON = os.environ.get('INU_TOOLS_PATH', str(addon_default))
if ADDON not in sys.path:
    sys.path.insert(0, ADDON)
import INU_tools
INU_tools.register()

from INU_tools.ops.dff_import import import_dff
from INU_tools.ops.ifp_import import import_ifp, apply_ifp_action

dff = str(root / 'assets/source/andre.dff')
ifp = str(root / 'assets/source/ped.ifp')
out = str(root / 'assets/models/andre_rigged.glb')

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.armatures, bpy.data.meshes, bpy.data.materials, bpy.data.actions):
    pass

print('IMPORT DFF', dff)
import_dff(dff, context=bpy.context, skip_2dfx=True)
bpy.context.view_layer.update()
arm = next((o for o in bpy.context.scene.objects if o.type == 'ARMATURE'), None)
print('ARMATURE', arm.name if arm else None)
print('OBJECTS', [(o.name, o.type) for o in bpy.context.scene.objects])
if arm is None:
    raise RuntimeError('DFF import did not create an armature')

print('IMPORT IFP', ifp)
actions = import_ifp(ifp, context=bpy.context)
print('ACTIONS', len(actions), [a.name for a in actions[:20]])
# Prefer a normal civilian walk cycle, otherwise the first walk-like action.
preferred = ['WALK_civi', 'WALK_player', 'WALK']
name = next((n for n in preferred if bpy.data.actions.get(n)), None)
if name is None:
    name = next((a.name for a in actions if 'WALK' in a.name.upper()), actions[0].name)
print('APPLY', name)
ok, msg = apply_ifp_action(name, arm, bpy.context)
print('APPLY RESULT', ok, msg)
if not ok:
    raise RuntimeError(msg)

# Also materialize the civilian running cycle so both original IFP actions
# are exported into the GLB and can be selected at runtime by the run button.
run_name = 'run_civi'
print('APPLY RUN', run_name)
ok, msg = apply_ifp_action(run_name, arm, bpy.context)
print('APPLY RUN RESULT', ok, msg)
if not ok:
    raise RuntimeError(msg)

# Export the original sneak/crouch locomotion for the mobile crouch toggle.
crouch_name = 'Player_Sneak'
print('APPLY CROUCH', crouch_name)
ok, msg = apply_ifp_action(crouch_name, arm, bpy.context)
print('APPLY CROUCH RESULT', ok, msg)
if not ok:
    raise RuntimeError(msg)

# Export the original jump launch animation for the mobile jump button.
jump_name = 'JUMP_launch'
print('APPLY JUMP', jump_name)
ok, msg = apply_ifp_action(jump_name, arm, bpy.context)
print('APPLY JUMP RESULT', ok, msg)
if not ok:
    raise RuntimeError(msg)

# Export the full unarmed fight combo from ped.ifp (GTA SA style).
# Runtime chains FightA_1 -> FightA_2 -> FightA_3 when the player keeps
# pressing / holding the punch button within the combo window.
for punch_name in ['FightA_1', 'FightA_2', 'FightA_3']:
    print('APPLY PUNCH', punch_name)
    ok, msg = apply_ifp_action(punch_name, arm, bpy.context)
    print('APPLY PUNCH RESULT', punch_name, ok, msg)
    if not ok:
        raise RuntimeError(f'{punch_name}: {msg}')

# Import the directional reactions and generic hit variants used by runtime combat.
HIT_REACTIONS = ['HIT_front', 'HIT_back', 'HIT_L', 'HIT_R', 'HitA_1', 'HitA_2', 'HitA_3']
for reaction_name in HIT_REACTIONS:
    print('APPLY HIT REACTION', reaction_name)
    ok, msg = apply_ifp_action(reaction_name, arm, bpy.context)
    print('APPLY HIT REACTION RESULT', reaction_name, ok, msg)
    if not ok:
        raise RuntimeError(f'{reaction_name}: {msg}')

# Movement is driven by CharacterBody3D, so keep the IFP pose animation but
# remove Root translation tracks. Otherwise the animation and gameplay both
# move the same character and it snaps/teleports while walking or running.
for action_name in ['WALK_civi', 'run_civi', 'Player_Sneak', 'JUMP_launch', 'FightA_1', 'FightA_2', 'FightA_3'] + HIT_REACTIONS:
    action = bpy.data.actions.get(action_name)
    if action is None:
        continue
    for fcurve in list(action.fcurves):
        if fcurve.data_path == 'pose.bones["Root"].location':
            action.fcurves.remove(fcurve)
    print('REMOVED ROOT MOTION', action_name)

# Put the animated armature and meshes in a clean export selection.
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type in {'ARMATURE', 'MESH'}:
        obj.select_set(True)
        obj.hide_viewport = False
        obj.hide_render = False
bpy.context.view_layer.objects.active = arm

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format='GLB',
    use_selection=True,
    export_animations=True,
    export_skins=True,
    export_def_bones=True,
    export_all_influences=True,
    export_materials='EXPORT',
)
print('EXPORTED', out)
