extends Node3D

const FRONT_WHEEL_LIFT := 0.63

func _ready() -> void:
    var front := _find_part(self, "wheel_front")
    var rear := _find_part(self, "wheel_rear")
    var mudguard := _find_part(self, "mudguard")
    if front != null:
        front.position.y += FRONT_WHEEL_LIFT
    if mudguard != null:
        mudguard.position.y += FRONT_WHEEL_LIFT
    if front != null and rear != null:
        var axle_y := global_position.y
        front.global_position.y = axle_y
        rear.global_position.y = axle_y
        front.rotation.x = 0.0
        rear.rotation.x = 0.0

func _find_part(root: Node, wanted: String) -> Node3D:
    for child in root.get_children():
        if child is Node3D and child.name.to_lower() == wanted.to_lower():
            return child as Node3D
        var found := _find_part(child, wanted)
        if found != null:
            return found
    return null
