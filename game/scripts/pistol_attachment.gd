extends Node3D
class_name AndrePistolAttachment

const PISTOL_SCENE := preload("res://assets/models/pistol/Pistol.fbx")
const HAND_BONES := [" R Hand", "R Hand", "Bip01 R Hand", "RightHand", "right_hand"]

var _attachment: BoneAttachment3D
var _weapon: Node3D
var _ready_for_character := false

func setup(character_visual: Node3D) -> bool:
    clear()
    if character_visual == null:
        return false
    var skeleton := _find_skeleton(character_visual)
    if skeleton == null:
        return false
    var hand_bone := ""
    for candidate in HAND_BONES:
        if skeleton.find_bone(candidate) >= 0:
            hand_bone = candidate
            break
    if hand_bone.is_empty():
        return false
    _attachment = BoneAttachment3D.new()
    _attachment.bone_name = hand_bone
    skeleton.add_child(_attachment)
    _attachment.name = "PistolHandAttachment"
    _weapon = PISTOL_SCENE.instantiate() as Node3D
    if _weapon == null:
        clear()
        return false
    _weapon.name = "CC0LowpolyPistol"
    # The source FBX is authored as a small prop; this offset keeps the grip
    # aligned with the right palm while the hand animations drive the pose.
    _weapon.position = Vector3(0.02, -0.01, -0.055)
    _weapon.rotation_degrees = Vector3(90.0, 0.0, 90.0)
    _weapon.scale = Vector3.ONE * 1.0
    _attachment.add_child(_weapon)
    _ready_for_character = true
    set_equipped(true)
    return true

func clear() -> void:
    _ready_for_character = false
    _weapon = null
    if is_instance_valid(_attachment):
        _attachment.free()
    _attachment = null

func set_equipped(equipped: bool) -> void:
    if is_instance_valid(_weapon):
        _weapon.visible = equipped

func is_equipped() -> bool:
    return _ready_for_character and is_instance_valid(_weapon) and _weapon.visible

func _find_skeleton(root: Node) -> Skeleton3D:
    if root is Skeleton3D:
        return root as Skeleton3D
    for child in root.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null
