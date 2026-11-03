extends RefCounted
class_name CostaVistaBuilder

const ROOT := "res://assets/maps/costa_vista/models/"

static func build(parent: Node3D) -> void:
	var city := Node3D.new()
	city.name = "CostaVistaCity"
	parent.add_child(city)
	_add_floor(city)
	_add_roads(city)
	_add_lawns(city)
	_add_props(city)
	_add_buildings(city)
	_add_vehicle(city)

static func _add_floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "CostaVistaGroundCollision"
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(220.0, 1.0, 220.0)
	collision.shape = shape
	collision.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.name = "CostaVistaGround"
	var ground := BoxMesh.new()
	ground.size = Vector3(220.0, 0.4, 220.0)
	mesh.mesh = ground
	mesh.position = Vector3(0.0, -0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c8a77b")
	material.roughness = 1.0
	ground.material = material
	parent.add_child(mesh)

static func _add_roads(parent: Node3D) -> void:
	for z in [-54.0, -18.0, 18.0, 54.0]:
		for x in [-72.0, -36.0, 0.0, 36.0, 72.0]:
			_add_model(parent, "roads/road_straight.glb", Vector3(x, 0.0, z), Vector3(1.0, 1.0, 1.0), 0.0)
	for x in [-54.0, -18.0, 18.0, 54.0]:
		for z in [-72.0, -36.0, 0.0, 36.0, 72.0]:
			_add_model(parent, "roads/road_straight.glb", Vector3(x, 0.02, z), Vector3(1.0, 1.0, 1.0), 90.0)
	for z in [-60.0, -24.0, 24.0, 60.0]:
		for x in [-72.0, -36.0, 0.0, 36.0, 72.0]:
			_add_model(parent, "roads/sidewalk_straight.glb", Vector3(x, 0.04, z - 7.0), Vector3(1.0, 1.0, 1.0), 0.0)
			_add_model(parent, "roads/sidewalk_straight.glb", Vector3(x, 0.04, z + 7.0), Vector3(1.0, 1.0, 1.0), 0.0)

static func _add_lawns(parent: Node3D) -> void:
	for x in [-36.0, 0.0, 36.0]:
		for z in [-36.0, 0.0, 36.0]:
			_add_model(parent, "grounds/ground_lawn.glb", Vector3(x, 0.08, z), Vector3(2.5, 1.0, 2.5), 0.0)

static func _add_props(parent: Node3D) -> void:
	for p in [Vector3(-42.0, 0.0, -42.0), Vector3(42.0, 0.0, -42.0), Vector3(-42.0, 0.0, 42.0), Vector3(42.0, 0.0, 42.0)]:
		_add_model(parent, "nature/palm_tall.glb", p, Vector3.ONE, 0.0)
		_add_model(parent, "props/bench_park.glb", p + Vector3(4.0, 0.0, 2.0), Vector3.ONE, 90.0)
		_add_model(parent, "street/street_lamp.glb", p + Vector3(-4.0, 0.0, -3.0), Vector3.ONE, 0.0)
	for p in [Vector3(-30.0, 0.0, -30.0), Vector3(30.0, 0.0, -30.0), Vector3(-30.0, 0.0, 30.0), Vector3(30.0, 0.0, 30.0)]:
		_add_model(parent, "nature/plant_agave.glb", p, Vector3.ONE, 0.0)
		_add_model(parent, "props/trash_bin.glb", p + Vector3(3.0, 0.0, 1.0), Vector3.ONE, 0.0)
	_add_model(parent, "street/traffic_signal_post.glb", Vector3(-8.0, 0.0, -8.0), Vector3.ONE, 0.0)
	_add_model(parent, "street/sign_stop_corner.glb", Vector3(8.0, 0.0, 8.0), Vector3.ONE, 180.0)
	_add_model(parent, "street/billboard_roof_fizz.glb", Vector3(54.0, 0.0, -54.0), Vector3.ONE, 0.0)
	_add_model(parent, "street/neon_open.glb", Vector3(-54.0, 0.0, 54.0), Vector3.ONE, 0.0)

static func _add_buildings(parent: Node3D) -> void:
	_add_model(parent, "buildings/burger_stand.glb", Vector3(-18.0, 0.0, -18.0), Vector3.ONE, 0.0)
	_add_model(parent, "buildings/burger_stand.glb", Vector3(18.0, 0.0, 18.0), Vector3.ONE, 180.0)
	_add_model(parent, "grounds/garden_wall.glb", Vector3(0.0, 0.0, 82.0), Vector3(1.5, 1.0, 1.0), 0.0)
	_add_model(parent, "nature/hedge_straight.glb", Vector3(-24.0, 0.0, 82.0), Vector3(1.5, 1.0, 1.0), 0.0)
	_add_model(parent, "nature/hedge_straight.glb", Vector3(24.0, 0.0, 82.0), Vector3(1.5, 1.0, 1.0), 0.0)

static func _add_vehicle(parent: Node3D) -> void:
	_add_model(parent, "vehicles/hatchback.glb", Vector3(6.0, 0.2, 4.0), Vector3.ONE, 25.0)

static func _add_model(parent: Node3D, relative_path: String, position: Vector3, scale: Vector3, yaw_degrees: float) -> Node3D:
	var packed := ResourceLoader.load(ROOT + relative_path) as PackedScene
	if packed == null:
		push_warning("Costa Vista model missing: " + relative_path)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	node.position = position
	node.scale = scale
	node.rotation_degrees.y = yaw_degrees
	parent.add_child(node)
	return node
