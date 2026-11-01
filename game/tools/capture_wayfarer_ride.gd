extends SceneTree
func _initialize() -> void:
    call_deferred("_capture")
func _capture() -> void:
    var scene := (load("res://scenes/third_person.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    var bike = scene.get_node("WayfarerR1200")
    bike.call("_start_mount")
    await create_timer(2.0).timeout
    var image := root.get_viewport().get_texture().get_image()
    var path := "/home/ubuntu/wayfarer_ride_debug.png"
    var err := image.save_png(path)
    print("CAPTURE", path, " ", error_string(err))
    quit(0 if err == OK else 1)
