extends Node3D
class_name MapBoundaryMountains

const EDGE_MARGIN := 90.0
const RANGE_WIDTH := 135.0
const WALL_THICKNESS := 12.0
const BASE_DEPTH := 45.0
const COLLISION_WALL_HEIGHT := 380.0
const RIDGE_MIN_HEIGHT := 230.0
const RIDGE_MAX_HEIGHT := 340.0
const SEGMENT_LENGTH := 120.0

const ROCK_COLORS := [
    Color(0.20, 0.23, 0.21, 1.0),
    Color(0.27, 0.29, 0.26, 1.0),
    Color(0.34, 0.35, 0.31, 1.0),
    Color(0.40, 0.40, 0.35, 1.0),
]

func build_for_region(region_id: String, bounds_min: Vector3, bounds_max: Vector3) -> bool:
    if bounds_max.x <= bounds_min.x or bounds_max.y <= bounds_min.y:
        return false

    var left := bounds_min.x - EDGE_MARGIN
    var right := bounds_max.x + EDGE_MARGIN
    var bottom := bounds_min.y - EDGE_MARGIN
    var top := bounds_max.y + EDGE_MARGIN
    var base_z := bounds_min.z - BASE_DEPTH

    var rng := RandomNumberGenerator.new()
    rng.seed = int(region_id.hash() & 0x7fffffff) + 1
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    _append_mountain_side(surface, Vector2(left - RANGE_WIDTH, bottom), Vector2(right + RANGE_WIDTH, bottom), Vector2(0.0, -1.0), base_z, rng)
    _append_mountain_side(surface, Vector2(left - RANGE_WIDTH, top), Vector2(right + RANGE_WIDTH, top), Vector2(0.0, 1.0), base_z, rng)
    _append_mountain_side(surface, Vector2(left, bottom - RANGE_WIDTH), Vector2(left, top + RANGE_WIDTH), Vector2(-1.0, 0.0), base_z, rng)
    _append_mountain_side(surface, Vector2(right, bottom - RANGE_WIDTH), Vector2(right, top + RANGE_WIDTH), Vector2(1.0, 0.0), base_z, rng)
    surface.generate_normals()
    var mountain_mesh := surface.commit()
    if mountain_mesh == null or mountain_mesh.get_surface_count() == 0:
        return false

    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.roughness = 1.0

    var mountain_visual := MeshInstance3D.new()
    mountain_visual.name = "MountainRangeVisual"
    mountain_visual.mesh = mountain_mesh
    mountain_visual.material_override = material
    mountain_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mountain_visual)

    var barrier := StaticBody3D.new()
    barrier.name = "MountainBoundaryCollision"
    barrier.collision_layer = 1
    barrier.collision_mask = 1
    add_child(barrier)
    var wall_height := COLLISION_WALL_HEIGHT
    var wall_z := base_z + wall_height * 0.5
    var x_span := right - left + RANGE_WIDTH * 2.0
    var y_span := top - bottom + RANGE_WIDTH * 2.0
    _add_wall(barrier, "SouthWall", Vector3((left + right) * 0.5, bottom - WALL_THICKNESS * 0.5, wall_z), Vector3(x_span, WALL_THICKNESS, wall_height))
    _add_wall(barrier, "NorthWall", Vector3((left + right) * 0.5, top + WALL_THICKNESS * 0.5, wall_z), Vector3(x_span, WALL_THICKNESS, wall_height))
    _add_wall(barrier, "WestWall", Vector3(left - WALL_THICKNESS * 0.5, (bottom + top) * 0.5, wall_z), Vector3(WALL_THICKNESS, y_span, wall_height))
    _add_wall(barrier, "EastWall", Vector3(right + WALL_THICKNESS * 0.5, (bottom + top) * 0.5, wall_z), Vector3(WALL_THICKNESS, y_span, wall_height))
    return true

func _append_mountain_side(surface: SurfaceTool, start: Vector2, finish: Vector2, outward: Vector2, base_z: float, rng: RandomNumberGenerator) -> void:
    var segment_count := maxi(2, int(ceil(start.distance_to(finish) / SEGMENT_LENGTH)))
    var ridge_heights := PackedFloat32Array()
    ridge_heights.resize(segment_count + 1)
    for point_index in range(segment_count + 1):
        ridge_heights[point_index] = base_z + rng.randf_range(RIDGE_MIN_HEIGHT, RIDGE_MAX_HEIGHT)

    var ridge_offset := outward * (RANGE_WIDTH * 0.5)
    var outer_offset := outward * RANGE_WIDTH
    for section in range(segment_count):
        var t0 := float(section) / float(segment_count)
        var t1 := float(section + 1) / float(segment_count)
        var point0 := start.lerp(finish, t0)
        var point1 := start.lerp(finish, t1)
        var inner0 := Vector3(point0.x, point0.y, base_z)
        var inner1 := Vector3(point1.x, point1.y, base_z)
        var ridge0 := Vector3(point0.x + ridge_offset.x, point0.y + ridge_offset.y, ridge_heights[section])
        var ridge1 := Vector3(point1.x + ridge_offset.x, point1.y + ridge_offset.y, ridge_heights[section + 1])
        var outer_point0 := point0 + outer_offset
        var outer_point1 := point1 + outer_offset
        var outer0 := Vector3(outer_point0.x, outer_point0.y, base_z)
        var outer1 := Vector3(outer_point1.x, outer_point1.y, base_z)
        _add_triangle(surface, inner0, inner1, ridge0, _random_rock_color(rng))
        _add_triangle(surface, inner1, ridge1, ridge0, _random_rock_color(rng))
        _add_triangle(surface, ridge0, ridge1, outer0, _random_rock_color(rng))
        _add_triangle(surface, ridge1, outer1, outer0, _random_rock_color(rng))

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
    surface.set_color(color)
    surface.add_vertex(a)
    surface.add_vertex(b)
    surface.add_vertex(c)

func _random_rock_color(rng: RandomNumberGenerator) -> Color:
    return ROCK_COLORS[rng.randi_range(0, ROCK_COLORS.size() - 1)]

func _add_wall(body: StaticBody3D, wall_name: String, center: Vector3, size: Vector3) -> void:
    var box := BoxShape3D.new()
    box.size = size
    var shape := CollisionShape3D.new()
    shape.name = wall_name
    shape.position = center
    shape.shape = box
    body.add_child(shape)
