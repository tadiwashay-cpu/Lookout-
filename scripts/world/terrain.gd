class_name Terrain
extends RefCounted
## The land: one height function (mountains, forest hills, suburb slopes, the
## flat city and harbour, the beach and the sea floor) flattened under roads.
## Drawn as chunked meshes with a splat shader; collides as one heightmap.

const CHUNK := 30                         # cells per mesh chunk (240 m)

static var _n_low := FastNoiseLite.new()
static var _n_hill := FastNoiseLite.new()
static var _n_ridge := FastNoiseLite.new()
static var roads: Roads
static var _heights := PackedFloat32Array()
static var _size := 0


static func setup(seed_value: int) -> void:
	_n_low.seed = seed_value
	_n_low.frequency = 0.004
	_n_hill.seed = seed_value + 1
	_n_hill.frequency = 0.007
	_n_hill.fractal_octaves = 3
	_n_ridge.seed = seed_value + 2
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.frequency = 0.0035
	_n_ridge.fractal_octaves = 4


## Land height without roads.
static func base_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := Layout.CITY_Y + 1.0 + _n_low.get_noise_2d(x, z) * 6.0
	# Suburb: gentle slopes.
	var sub := Layout.in_rect_soft(p, Layout.SUBURB_RECT, 90.0)
	h = lerpf(h, Layout.CITY_Y + 4.0 + _n_low.get_noise_2d(x * 0.6, z * 0.6) * 5.0, sub)
	# Forest hills.
	var forest := Layout.in_rect_soft(p, Layout.FOREST_RECT, 120.0)
	h += forest * (14.0 + _n_hill.get_noise_2d(x, z) * 22.0)
	# Mountains: north, west and south edges (they also close off the map).
	var north := smoothstep(-520.0, -760.0, z)
	var west := smoothstep(-990.0, -1130.0, x)
	var south := smoothstep(1060.0, 1170.0, z)
	var mountain := maxf(maxf(north, west), south)
	if mountain > 0.0:
		var ridge := (_n_ridge.get_noise_2d(x, z) + 1.0) * 0.5
		# A valley follows the coast highway: the pass, not a canyon.
		var valley := smoothstep(30.0, 280.0, _pass_distance(p))
		h += mountain * (40.0 + ridge * ridge * 300.0) * (0.6 + 0.4 * mountain) * lerpf(0.08, 1.0, valley)
	# Sea: the land drops away east of the shore (beach first).
	var sea := smoothstep(Layout.SHORE_X + 10.0, Layout.SHORE_X + 90.0, x)
	h = lerpf(h, -12.0, sea)
	# City and harbour are flat.
	var flat := maxf(Layout.in_rect_soft(p, Layout.CITY_RECT, 70.0), Layout.in_rect_soft(p, Layout.HARBOUR_RECT, 10.0))
	h = lerpf(h, Layout.CITY_Y - 0.02, flat)
	return h


static func _pass_distance(p: Vector2) -> float:
	var pts: Array = Layout.ROADS["coast_highway"]
	var best := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var ab: Vector2 = pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func height(x: float, z: float) -> float:
	var h := base_height(x, z)
	if roads:
		var r := roads.influence(x, z)
		if r.x > 0.0:
			h = lerpf(h, r.y - 0.25, r.x)
	return h


## Height at any point, from the precomputed grid (fast, matches collision).
static func height_at(x: float, z: float) -> float:
	if _size == 0:
		return height(x, z)
	var gx := clampf((x + Layout.HALF) / Layout.CELL, 0.0, _size - 1.001)
	var gz := clampf((z + Layout.HALF) / Layout.CELL, 0.0, _size - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := _heights[iz * _size + ix]
	var h10 := _heights[iz * _size + ix + 1]
	var h01 := _heights[(iz + 1) * _size + ix]
	var h11 := _heights[(iz + 1) * _size + ix + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


static func build(parent: Node3D) -> void:
	_size = int(Layout.HALF * 2.0 / Layout.CELL) + 1
	_heights.resize(_size * _size)
	for iz in _size:
		var z := -Layout.HALF + iz * Layout.CELL
		for ix in _size:
			_heights[iz * _size + ix] = height(-Layout.HALF + ix * Layout.CELL, z)
	# Collision: one heightmap (uniform scale = cell size).
	var shape := HeightMapShape3D.new()
	shape.map_width = _size
	shape.map_depth = _size
	var scaled := PackedFloat32Array()
	scaled.resize(_heights.size())
	for i in _heights.size():
		scaled[i] = _heights[i] / Layout.CELL
	shape.map_data = scaled
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Game.L_WORLD
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3.ONE * Layout.CELL
	body.add_child(col)
	parent.add_child(body)
	# Meshes.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/terrain.gdshader")
	mat.set_shader_parameter("grass_d", Mats.tex("aerial_grass_rock", "diff"))
	mat.set_shader_parameter("grass2_d", Mats.tex("grass_ground", "diff"))
	mat.set_shader_parameter("grass_n", Mats.tex("grass_ground", "nor"))
	mat.set_shader_parameter("forest_d", Mats.tex("forest_ground_04", "diff"))
	mat.set_shader_parameter("sand_d", Mats.tex("coast_sand_01", "diff"))
	mat.set_shader_parameter("rock_d", Mats.tex("aerial_rocks_02", "diff"))
	mat.set_shader_parameter("rock_n", Mats.tex("aerial_rocks_02", "nor"))
	mat.set_shader_parameter("urban_d", Mats.tex("brushed_concrete", "diff"))
	var chunks := (_size - 1) / CHUNK
	for cz in chunks:
		for cx in chunks:
			parent.add_child(_chunk(cx, cz, mat))


static func _chunk(cx: int, cz: int, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for iz in CHUNK + 1:
		for ix in CHUNK + 1:
			var gx := x0 + ix
			var gz := z0 + iz
			var wx := -Layout.HALF + gx * Layout.CELL
			var wz := -Layout.HALF + gz * Layout.CELL
			var h := _heights[gz * _size + gx]
			var hl := _heights[gz * _size + maxi(gx - 1, 0)]
			var hr := _heights[gz * _size + mini(gx + 1, _size - 1)]
			var hd := _heights[maxi(gz - 1, 0) * _size + gx]
			var hu := _heights[mini(gz + 1, _size - 1) * _size + gx]
			var n := Vector3(hl - hr, 2.0 * Layout.CELL, hd - hu).normalized()
			var p := Vector2(wx, wz)
			var forest := Layout.in_rect_soft(p, Layout.FOREST_RECT, 60.0)
			var sand := smoothstep(Layout.SHORE_X - 5.0, Layout.SHORE_X + 25.0, wx) * (1.0 - Layout.in_rect_soft(p, Layout.HARBOUR_RECT, 5.0))
			sand = maxf(sand, 1.0 - smoothstep(-2.0, 0.6, h))
			var urban := maxf(Layout.in_rect_soft(p, Layout.CITY_RECT, 20.0), Layout.in_rect_soft(p, Layout.HARBOUR_RECT, 5.0))
			st.set_color(Color(forest, sand, urban))
			st.set_normal(n)
			st.set_uv(Vector2(wx, wz) * 0.05)
			st.add_vertex(Vector3(wx, h, wz))
	var row := CHUNK + 1
	for iz in CHUNK:
		for ix in CHUNK:
			var a := iz * row + ix
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + row)
			st.add_index(a + 1)
			st.add_index(a + row + 1)
			st.add_index(a + row)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.visibility_range_end = Game.view_distance + 250.0
	mi.name = "Land_%d_%d" % [cx, cz]
	return mi
