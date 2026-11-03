extends Node3D
class_name MapBoundaryMountains

# Anel contínuo de montanhas ao redor da região do mapa.
# O nó pai (Gta3MapStreamer) está girado -90° em X, então aqui Z é "para cima"
# e o plano do chão é X/Y (mesmas coordenadas dos bounds do catálogo).

const EDGE_MARGIN := 90.0              # folga entre o último tile e o pé da montanha
const RANGE_WIDTH := 520.0             # largura da faixa de montanha (do pé ao lado de fora)
const PEAK_HEIGHT := 260.0             # altura média dos picos acima do chão
const FOOT_SINK := 20.0                # quanto o pé da montanha fica enterrado (evita fresta)
const CELL_SIZE := 30.0                # resolução da malha
const NOISE_FREQUENCY := 0.0035
const WALL_THICKNESS := 12.0
const COLLISION_WALL_HEIGHT := 400.0

var _rect := Rect2()
var _ground_z := 0.0
var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
var _noise: FastNoiseLite
var _surface: SurfaceTool
var _vertex_index := PackedInt32Array()
var _vertex_count := 0


func build_for_region(region_id: String, bounds_min: Vector3, bounds_max: Vector3) -> bool:
	if bounds_max.x <= bounds_min.x or bounds_max.y <= bounds_min.y:
		return false

	var inner_min := Vector2(bounds_min.x, bounds_min.y) - Vector2.ONE * EDGE_MARGIN
	var inner_size := Vector2(bounds_max.x - bounds_min.x, bounds_max.y - bounds_min.y) + Vector2.ONE * (EDGE_MARGIN * 2.0)
	_rect = Rect2(inner_min, inner_size)
	_ground_z = bounds_min.z

	var outer := _rect.grow(RANGE_WIDTH)
	_origin = outer.position
	_cols = int(ceil(outer.size.x / CELL_SIZE))
	_rows = int(ceil(outer.size.y / CELL_SIZE))

	_noise = FastNoiseLite.new()
	_noise.seed = int(region_id.hash() & 0x7fffffff) + 1
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = NOISE_FREQUENCY
	_noise.fractal_octaves = 4

	_vertex_index = PackedInt32Array()
	_vertex_index.resize((_cols + 1) * (_rows + 1))
	_vertex_index.fill(-1)
	_vertex_count = 0

	_surface = SurfaceTool.new()
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var emitted_cells := 0
	for row in range(_rows):
		for col in range(_cols):
			var d00 := _distance_outside(_grid_point(col, row))
			var d10 := _distance_outside(_grid_point(col + 1, row))
			var d01 := _distance_outside(_grid_point(col, row + 1))
			var d11 := _distance_outside(_grid_point(col + 1, row + 1))
			var d_min := minf(minf(d00, d10), minf(d01, d11))
			var d_max := maxf(maxf(d00, d10), maxf(d01, d11))
			# Célula toda dentro do mapa, ou toda além da faixa: não gera nada.
			if d_max <= 0.0 or d_min >= RANGE_WIDTH:
				continue
			var v00 := _vertex(col, row)
			var v10 := _vertex(col + 1, row)
			var v01 := _vertex(col, row + 1)
			var v11 := _vertex(col + 1, row + 1)
			_surface.add_index(v00)
			_surface.add_index(v01)
			_surface.add_index(v10)
			_surface.add_index(v10)
			_surface.add_index(v01)
			_surface.add_index(v11)
			emitted_cells += 1

	if emitted_cells == 0:
		return false

	_surface.generate_normals()
	var mountain_mesh := _surface.commit()
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

	_build_collision_walls()
	return true


# Ponto do plano do chão para um vértice da grade.
func _grid_point(col: int, row: int) -> Vector2:
	return _origin + Vector2(col, row) * CELL_SIZE


# Distância até o retângulo do mapa (0 = dentro). Os cantos ficam arredondados.
func _distance_outside(point: Vector2) -> float:
	var dx := maxf(maxf(_rect.position.x - point.x, 0.0), point.x - _rect.end.x)
	var dy := maxf(maxf(_rect.position.y - point.y, 0.0), point.y - _rect.end.y)
	return Vector2(dx, dy).length()


# Altura (relativa ao chão) para uma distância e posição.
func _height_at(point: Vector2, distance: float) -> float:
	var t := clampf(distance / RANGE_WIDTH, 0.0, 1.0)
	var rise := smoothstep(0.0, 0.55, t)
	var fall := 1.0 - smoothstep(0.55, 1.0, t)
	var shape := rise * fall
	var n := _noise.get_noise_2d(point.x, point.y) * 0.5 + 0.5
	var amplitude := PEAK_HEIGHT * (0.55 + 0.6 * n)
	return -FOOT_SINK + shape * (amplitude + FOOT_SINK)


func _vertex(col: int, row: int) -> int:
	var slot := row * (_cols + 1) + col
	if _vertex_index[slot] >= 0:
		return _vertex_index[slot]
	var point := _grid_point(col, row)
	var height := _height_at(point, _distance_outside(point))
	_surface.set_color(_rock_color(height))
	_surface.add_vertex(Vector3(point.x, point.y, _ground_z + height))
	_vertex_index[slot] = _vertex_count
	_vertex_count += 1
	return _vertex_index[slot]


func _rock_color(height: float) -> Color:
	var f := clampf((height + FOOT_SINK) / (PEAK_HEIGHT * 1.15), 0.0, 1.0)
	var foot := Color(0.17, 0.25, 0.15, 1.0)
	var rock := Color(0.34, 0.32, 0.28, 1.0)
	var high := Color(0.58, 0.57, 0.53, 1.0)
	var peak := Color(0.88, 0.88, 0.86, 1.0)
	if f < 0.4:
		return foot.lerp(rock, f / 0.4)
	if f < 0.75:
		return rock.lerp(high, (f - 0.4) / 0.35)
	return high.lerp(peak, (f - 0.75) / 0.25)


func _build_collision_walls() -> void:
	var barrier := StaticBody3D.new()
	barrier.name = "MountainBoundaryCollision"
	barrier.collision_layer = 1
	barrier.collision_mask = 1
	add_child(barrier)

	var wall_z := _ground_z - FOOT_SINK + COLLISION_WALL_HEIGHT * 0.5
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
