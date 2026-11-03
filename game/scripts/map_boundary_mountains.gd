extends Node3D
class_name MapBoundaryInvisible

## Barreira física invisível ao redor da região ativa do mapa.
## O MapStreamer está girado -90° em X; os bounds do catálogo continuam no
## plano local X/Y e o eixo Z local representa a altura do mundo.

const EDGE_MARGIN := 90.0
const WALL_THICKNESS := 12.0
const COLLISION_WALL_HEIGHT := 400.0

var _rect := Rect2()
var _ground_z := 0.0


func build_for_region(_region_id: String, bounds_min: Vector3, bounds_max: Vector3) -> bool:
	if bounds_max.x <= bounds_min.x or bounds_max.y <= bounds_min.y:
		return false

	var inner_min := Vector2(bounds_min.x, bounds_min.y) - Vector2.ONE * EDGE_MARGIN
	var inner_size := Vector2(bounds_max.x - bounds_min.x, bounds_max.y - bounds_min.y) + Vector2.ONE * (EDGE_MARGIN * 2.0)
	_rect = Rect2(inner_min, inner_size)
	_ground_z = bounds_min.z
	_build_collision_walls()
	return true


func _build_collision_walls() -> void:
	var barrier := StaticBody3D.new()
	barrier.name = "InvisibleMapBoundary"
	barrier.collision_layer = 1
	barrier.collision_mask = 1
	add_child(barrier)

	var wall_z := _ground_z - 20.0 + COLLISION_WALL_HEIGHT * 0.5
	var left := _rect.position.x
	var right := _rect.end.x
	var bottom := _rect.position.y
	var top := _rect.end.y
	var center_x := (left + right) * 0.5
	var center_y := (bottom + top) * 0.5
	var x_span := (right - left) + WALL_THICKNESS * 2.0
	var y_span := (top - bottom) + WALL_THICKNESS * 2.0
	_add_wall(barrier, "SouthWall", Vector3(center_x, bottom - WALL_THICKNESS * 0.5, wall_z), Vector3(x_span, WALL_THICKNESS, COLLISION_WALL_HEIGHT))
	_add_wall(barrier, "NorthWall", Vector3(center_x, top + WALL_THICKNESS * 0.5, wall_z), Vector3(x_span, WALL_THICKNESS, COLLISION_WALL_HEIGHT))
	_add_wall(barrier, "WestWall", Vector3(left - WALL_THICKNESS * 0.5, center_y, wall_z), Vector3(WALL_THICKNESS, y_span, COLLISION_WALL_HEIGHT))
	_add_wall(barrier, "EastWall", Vector3(right + WALL_THICKNESS * 0.5, center_y, wall_z), Vector3(WALL_THICKNESS, y_span, COLLISION_WALL_HEIGHT))


func _add_wall(body: StaticBody3D, wall_name: String, center: Vector3, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.name = wall_name
	shape.position = center
	shape.shape = box
	body.add_child(shape)
