extends SceneTree

func _initialize() -> void:
    call_deferred("_capture")

func _capture() -> void:
    var scene := (load("res://scenes/third_person.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    var bike = scene.get_node("Pop100e2024")
    bike.call("_start_mount")
    await create_timer(1.4).timeout
    var camera := scene.get_node("Player/Camera3D") as Camera3D
    camera.global_position = bike.global_position + Vector3(4.0, 1.5, 0.0)
    camera.look_at(bike.global_position + Vector3(0.0, 0.55, 0.0), Vector3.UP)
    await process_frame
    var image := root.get_viewport().get_texture().get_image()
    var path := "/home/ubuntu/bike_mount_side_debug.png"
    var err := image.save_png(path)
    print("CAPTURE", path, " ", error_string(err))
    quit(0 if err == OK else 1)
