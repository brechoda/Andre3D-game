extends SceneTree
func _initialize() -> void:
    call_deferred("_check")
func _check() -> void:
    var scene := (load("res://scenes/third_person.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    await process_frame
    var bike := scene.get_node("Pop100e2024")
    print("BIKE_POS ", bike.global_position)
    _walk(bike)
    quit()
func _walk(n: Node) -> void:
    if n is MeshInstance3D and n.mesh != null:
        if n.name in ["wheel_front", "wheel_rear", "banco", "chassis", "rabeta"]:
            print("PARTINFO ", n.name, " POS ", n.global_position, " ROT ", n.global_rotation, " AABB ", n.get_aabb())
        var a := (n as MeshInstance3D).get_aabb()
        var t := (n as MeshInstance3D).global_transform
        var pts: Array[Vector3] = []
        for x in [a.position.x, a.end.x]:
            for y in [a.position.y, a.end.y]:
                for z in [a.position.z, a.end.z]:
                    pts.append(t * Vector3(x, y, z))
        var min_y := INF
        var max_y := -INF
        for p in pts:
            min_y = minf(min_y, p.y)
            max_y = maxf(max_y, p.y)
        print("PART ", n.name, " Y ", min_y, "..", max_y)
    for c in n.get_children():
        _walk(c)
