extends Node3D
class_name AndreRifleAttachment

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
    _attachment.name = "M4HandAttachment"
    _weapon = _build_m4()
    _weapon.name = "LowPolyM4"
    _weapon.position = Vector3(0.04, -0.02, -0.10)
    _weapon.rotation_degrees = Vector3(90.0, 0.0, 90.0)
    _weapon.scale = Vector3.ONE * 0.85
    _attachment.add_child(_weapon)
    _ready_for_character = true
    set_equipped(false)
    return true

func _build_m4() -> Node3D:
    var root := Node3D.new()
    var dark := StandardMaterial3D.new()
    dark.albedo_color = Color("20252b")
    dark.roughness = 0.82
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color("4b5359")
    metal.roughness = 0.65
    _add_box(root, "Receiver", Vector3(0.13, 0.13, 0.42), Vector3(0.0, 0.0, -0.08), dark)
    _add_box(root, "Stock", Vector3(0.10, 0.10, 0.28), Vector3(0.0, 0.01, 0.25), dark)
    _add_box(root, "Handguard", Vector3(0.11, 0.11, 0.38), Vector3(0.0, 0.0, -0.47), dark)
    _add_box(root, "Magazine", Vector3(0.10, 0.22, 0.15), Vector3(0.0, -0.12, -0.02), dark)
    _add_box(root, "Grip", Vector3(0.09, 0.22, 0.10), Vector3(0.0, -0.15, 0.13), dark)
    _add_cylinder(root, "Barrel", 0.035, 0.34, Vector3(0.0, 0.0, -0.82), metal)
    _add_box(root, "FrontSight", Vector3(0.06, 0.10, 0.07), Vector3(0.0, 0.07, -0.67), metal)
    return root

func _add_box(root: Node3D, node_name: String, size: Vector3, pos: Vector3, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    var item := MeshInstance3D.new()
    item.name = node_name
    item.mesh = mesh
    item.material_override = material
    item.position = pos
    root.add_child(item)

func _add_cylinder(root: Node3D, node_name: String, radius: float, height: float, pos: Vector3, material: Material) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    var item := MeshInstance3D.new()
    item.name = node_name
    item.mesh = mesh
    item.material_override = material
    item.position = pos
    item.rotation_degrees.x = 90.0
    root.add_child(item)

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
