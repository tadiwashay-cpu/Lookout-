class_name WorldRegions
extends RefCounted
## Everything outside the city grid, all connected:
##   city -> HARBOR (east waterfront)
##   city -> HIGHWAY (curving north past the harbour) -> FOREST (hills,
##   pines, dirt road) -> SUBURB (houses, lawns, cul-de-sac streets)

const WORLD_LAYER := 1

# Harbour: quay strip east of the city, water beyond.
const QUAY_X0 := 265.0
const QUAY_EDGE := 335.0
const WATER_RECT := Rect2(335.0, -700.0, 800.0, 1200.0)

# Highway centreline control points (x, z), from the city's north edge.
const HIGHWAY_POINTS := [
	Vector2(-204, -149), Vector2(-262, -149), Vector2(-322, -172), Vector2(-350, -255), Vector2(-285, -360),
	Vector2(-120, -430), Vector2(60, -470), Vector2(200, -545),
	Vector2(235, -660), Vector2(80, -780), Vector2(-100, -880), Vector2(-250, -990), Vector2(-330, -1100),
]
const HIGHWAY_HALF_WIDTH := 11.0
const HIGHWAY_Y := 0.25

# Forest terrain and its road (continues the highway to the suburb).
const FOREST_RECT := Rect2(-760.0, -1800.0, 720.0, 720.0)
const FOREST_ROAD := [
	Vector2(-330, -1100), Vector2(-380, -1250), Vector2(-300, -1420),
	Vector2(-450, -1580), Vector2(-650, -1650), Vector2(-770, -1640),
]
const ROAD_Y := 0.35

# Suburb west of the forest.
const SUBURB_RECT := Rect2(-1160.0, -1800.0, 400.0, 320.0)
const SUBURB_MAIN_Z := -1640.0

var w: World
var b: MeshBatcher
var rng: RandomNumberGenerator
var highway_samples: Array[Vector3] = []
var forest_road_samples: Array[Vector3] = []
var _noise := FastNoiseLite.new()


func _init(world: World) -> void:
	w = world
	b = world.batcher
	rng = world.rng
	_noise.seed = 1977
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3


func build() -> void:
	_harbor()
	_highway()
	_forest()
	_suburb()


# ------------------------------------------------------------------ helpers

static func catmull(points: Array, step: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in points.size() - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		var steps := maxi(int(p1.distance_to(p2) / step), 1)
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append(Vector3(p.x, 0.0, p.y))
	var last: Vector2 = points[points.size() - 1]
	out.append(Vector3(last.x, 0.0, last.y))
	return out


## Distance from a point to a polyline (x/z).
static func distance_to_path(p: Vector2, path: Array[Vector3]) -> float:
	var best := INF
	for i in path.size() - 1:
		var a := Vector2(path[i].x, path[i].z)
		var c := Vector2(path[i + 1].x, path[i + 1].z)
		var ab := c - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Builds a flat ribbon (road surface) along samples with a collider.
func _ribbon(samples: Array[Vector3], half_width: float, key: String, solid: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in samples.size() - 1:
		var a := samples[i]
		var c := samples[i + 1]
		var dir := (c - a)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x) * half_width
		var dir2 := dir
		if i + 2 < samples.size():
			dir2 = (samples[i + 2] - c)
			dir2.y = 0.0
			dir2 = dir2.normalized()
		var side2 := Vector3(-dir2.z, 0.0, dir2.x) * half_width
		var quad := [a - side, a + side, c + side2, c - side2]
		for tri: Array in [[quad[0], quad[2], quad[1]], [quad[0], quad[3], quad[2]]]:
			for v: Vector3 in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z) * 0.1)
				st.add_vertex(v)
				faces.append(v)
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = b.materials.get(key)
	w.add_child(instance)
	if solid:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		w.add_child(body)


# ------------------------------------------------------------------ harbour

func _harbor() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = WATER_RECT.size
	water.mesh = plane
	water.material_override = b.materials.get("water")
	water.position = Vector3(WATER_RECT.get_center().x, -1.2, WATER_RECT.get_center().y)
	w.add_child(water)
	w.map_water = WATER_RECT

	# Quay wall
	b.box(Vector3(1.5, 4.0, 900.0), Vector3(QUAY_EDGE, -1.9, -100.0), "concrete")
	b.box(Vector3(QUAY_EDGE - QUAY_X0, 0.1, 900.0), Vector3((QUAY_X0 + QUAY_EDGE) * 0.5, 0.05, -100.0), "concrete", false)
	# Sheds on the north quay
	for i in 3:
		var z := -480.0 + i * 85.0
		b.box(Vector3(26.0, 12.0, 64.0), Vector3(298.0, 6.0, z), "shed")
		b.box(Vector3(27.0, 0.6, 65.0), Vector3(298.0, 12.2, z), "roof", false)
		w.add_region_point("harbor", Vector3(320.0, 0.3, z + 40.0))
	# Container yard
	var colors := ["container_red", "container_blue", "container_teal", "container_grey"]
	for row in 6:
		for col in 9:
			var height := rng.randi_range(1, 4)
			var base := Vector3(276.0 + row * 9.0, 0.0, -40.0 + col * 15.0)
			for level in height:
				b.box(Vector3(2.5, 2.6, 12.0), base + Vector3(0, 1.3 + level * 2.6, 0), colors[rng.randi() % colors.size()], false)
			b.collider_box(Vector3(2.5, 2.6 * height, 12.0), base + Vector3(0, 1.3 * height, 0))
	for i in 6:
		w.add_region_point("harbor", Vector3(330.0, 0.3, -30.0 + i * 25.0))
	# Gantry cranes at the quay edge
	for i in 3:
		var z := 0.0 + i * 55.0 - 200.0
		for leg: float in [-6.0, 6.0]:
			b.box(Vector3(1.4, 38.0, 1.4), Vector3(QUAY_EDGE - 8.0, 19.0, z + leg), "crane")
			b.box(Vector3(1.4, 38.0, 1.4), Vector3(QUAY_EDGE + 4.0, 19.0, z + leg), "crane", false)
		b.box(Vector3(70.0, 3.0, 4.0), Vector3(QUAY_EDGE + 20.0, 39.0, z), "crane", false)
	# Piers and the docked ship
	for pier_z: float in [-150.0, 250.0]:
		b.box(Vector3(120.0, 1.0, 14.0), Vector3(QUAY_EDGE + 60.0, -0.5, pier_z), "concrete")
		w.add_region_point("harbor", Vector3(QUAY_EDGE + 100.0, 0.3, pier_z))
	var hull_center := Vector3(QUAY_EDGE + 75.0, 3.0, -150.0 + 20.0)
	b.box(Vector3(140.0, 10.0, 22.0), hull_center, "ship_hull")
	var bow := PrismMesh.new()
	bow.size = Vector3(22.0, 10.0, 18.0)
	b.mesh(bow, Transform3D(Basis(Vector3.FORWARD, -PI * 0.5).rotated(Vector3.UP, PI * 0.5), hull_center + Vector3(79.0, 0, 0)), "ship_hull")
	b.box(Vector3(18.0, 14.0, 18.0), hull_center + Vector3(-55.0, 12.0, 0), "white_paint")
	b.box(Vector3(130.0, 0.4, 20.0), hull_center + Vector3(0, 5.1, 0), "ship_deck")
	w.extraction_points["harbor"] = Vector3(QUAY_EDGE + 110.0, 0.4, 250.0)
	w.supercar_spot = Vector3(318.0, 0.5, -520.0)   # behind the northern shed
	w.map_lines.append(PackedVector2Array([Vector2(QUAY_EDGE, -550), Vector2(QUAY_EDGE, 350)]))


# ------------------------------------------------------------------ highway

func _highway() -> void:
	highway_samples = catmull(HIGHWAY_POINTS, 6.0)
	for i in highway_samples.size():
		# Meets the city highway's own surface, then rises to its usual height.
		highway_samples[i].y = lerpf(0.07, HIGHWAY_Y, clampf(i / 8.0, 0.0, 1.0))
	_ribbon(highway_samples, HIGHWAY_HALF_WIDTH, "asphalt", true)
	# Guardrails, dashes and lights along the curve
	var dash := BoxMesh.new()
	dash.size = Vector3(0.18, 0.02, 3.0)
	var dashes: Array[Transform3D] = []
	for i in highway_samples.size() - 1:
		var a := highway_samples[i]
		var c := highway_samples[i + 1]
		var dir := (c - a)
		dir.y = 0.0
		var length := dir.length()
		dir = dir.normalized()
		var yaw := atan2(dir.x, dir.z)
		var side := Vector3(-dir.z, 0.0, dir.x)
		var mid := (a + c) * 0.5
		for s: float in [-1.0, 1.0]:
			b.box(Vector3(0.3, 0.8, length + 0.2), mid + side * s * (HIGHWAY_HALF_WIDTH - 0.3) + Vector3.UP * 0.4, "metal", true, yaw)
		if i % 2 == 0:
			for lane: float in [-5.5, 5.5]:
				dashes.append(Transform3D(Basis(Vector3.UP, yaw), mid + side * lane + Vector3.UP * 0.02))
			dashes.append(Transform3D(Basis(Vector3.UP, yaw), mid + Vector3.UP * 0.02))
		if i % 8 == 0:
			var s_side := 1.0 if (i / 8) % 2 == 0 else -1.0
			w.add_street_light(mid + side * s_side * (HIGHWAY_HALF_WIDTH + 0.6), -s_side, 10.0)
		if i % 12 == 6:
			w.add_region_point("highway", mid + side * 7.5 + Vector3.UP * 0.3)
	w.add_multimesh(dash, dashes, "line")
	var pts := PackedVector2Array()
	for p in highway_samples:
		pts.append(Vector2(p.x, p.z))
	w.map_lines.append(pts)
	var rest := highway_samples[highway_samples.size() / 2]
	w.extraction_points["highway"] = rest + Vector3(0, 0.3, 0)


# ------------------------------------------------------------------- forest

func forest_height(x: float, z: float) -> float:
	if not FOREST_RECT.has_point(Vector2(x, z)):
		return 0.0
	var edge := minf(minf(x - FOREST_RECT.position.x, FOREST_RECT.end.x - x), minf(z - FOREST_RECT.position.y, FOREST_RECT.end.y - z))
	var fade := smoothstep(0.0, 90.0, edge)
	var hills := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 26.0 + 2.0
	var h := hills * fade
	var road := distance_to_path(Vector2(x, z), forest_road_samples)
	return lerpf(ROAD_Y - 0.05, h, smoothstep(9.0, 30.0, road))


func _forest() -> void:
	forest_road_samples = catmull(FOREST_ROAD, 8.0)
	var cells := 120
	var size := FOREST_RECT.size.x
	var cell := size / cells
	var origin := Vector3(FOREST_RECT.position.x, 0.0, FOREST_RECT.position.y)
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for zi in cells + 1:
		for xi in cells + 1:
			heights[zi * (cells + 1) + xi] = forest_height(origin.x + xi * cell, origin.z + zi * cell)
	# Visual terrain mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in cells:
		for xi in cells:
			var corners := [Vector2i(xi, zi), Vector2i(xi + 1, zi), Vector2i(xi + 1, zi + 1), Vector2i(xi, zi + 1)]
			var v: Array[Vector3] = []
			for c: Vector2i in corners:
				v.append(origin + Vector3(c.x * cell, heights[c.y * (cells + 1) + c.x], c.y * cell))
			for tri: Array in [[v[0], v[1], v[2]], [v[0], v[2], v[3]]]:
				var n := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).normalized()
				if n.y < 0.0:
					n = -n
				for p: Vector3 in tri:
					st.set_normal(n)
					st.add_vertex(p)
	st.index()
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.material_override = b.materials.get("forest_floor")
	w.add_child(terrain)
	# Collision: heightmap (uniform-scaled grid, heights pre-divided by the cell size)
	var hm := HeightMapShape3D.new()
	hm.map_width = cells + 1
	hm.map_depth = cells + 1
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / cell
	hm.map_data = scaled
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = hm
	collision.scale = Vector3.ONE * cell
	body.position = origin + Vector3(size * 0.5, 0.0, size * 0.5)
	body.add_child(collision)
	w.add_child(body)
	# Dirt road on top
	var road: Array[Vector3] = []
	for p in forest_road_samples:
		road.append(Vector3(p.x, ROAD_Y, p.z))
	_ribbon(road, 5.5, "dirt", false)
	var pts := PackedVector2Array()
	for p in road:
		pts.append(Vector2(p.x, p.z))
	w.map_lines.append(pts)
	w.map_forest = FOREST_RECT
	# Trees
	var placed := 0
	var attempts := 0
	while placed < 1800 and attempts < 9000:
		attempts += 1
		var x := rng.randf_range(FOREST_RECT.position.x + 10, FOREST_RECT.end.x - 10)
		var z := rng.randf_range(FOREST_RECT.position.y + 10, FOREST_RECT.end.y - 10)
		if distance_to_path(Vector2(x, z), forest_road_samples) < 12.0:
			continue
		w.add_tree(Vector3(x, forest_height(x, z) - 0.2, z), rng.randf_range(0.9, 1.6), true)
		placed += 1
	# Ranger lookout tower on the highest sampled ground near the middle
	var top := Vector3(-380, 0, -1450)
	top.y = forest_height(top.x, top.z)
	b.box(Vector3(5.0, 16.0, 5.0), top + Vector3(0, 8.0, 0), "wood")
	b.box(Vector3(7.0, 3.0, 7.0), top + Vector3(0, 17.5, 0), "wood")
	for i in range(1, forest_road_samples.size() - 1, 6):
		w.add_region_point("forest", forest_road_samples[i] + Vector3(0, 0.6, 0))
	w.extraction_points["forest"] = forest_road_samples[forest_road_samples.size() / 2] + Vector3(0, 0.6, 0)


# ------------------------------------------------------------------- suburb

func _suburb() -> void:
	var r := SUBURB_RECT
	# Main road (continues the forest road) and cross streets
	b.box(Vector3(r.size.x, 0.06, 12.0), Vector3(r.get_center().x, 0.03, SUBURB_MAIN_Z), "asphalt", false)
	w.map_lines.append(PackedVector2Array([Vector2(r.position.x, SUBURB_MAIN_Z), Vector2(r.end.x, SUBURB_MAIN_Z)]))
	var cross_xs: Array[float] = []
	var x := r.position.x + 50.0
	while x < r.end.x - 20.0:
		cross_xs.append(x)
		b.box(Vector3(10.0, 0.06, r.size.y), Vector3(x, 0.03, r.get_center().y), "asphalt", false)
		w.map_lines.append(PackedVector2Array([Vector2(x, r.position.y), Vector2(x, r.end.y)]))
		x += 100.0
	# Houses facing the streets
	for street_x in cross_xs:
		var z := r.position.y + 18.0
		while z < r.end.y - 12.0:
			if absf(z - SUBURB_MAIN_Z) > 20.0:
				for side: float in [-1.0, 1.0]:
					_house(Vector3(street_x + side * 22.0, 0.0, z), side)
			z += 24.0
	w.extraction_points["suburb"] = Vector3(cross_xs[cross_xs.size() - 1], 0.3, r.position.y + 6.0)
	w.add_region_point("suburb", Vector3(r.get_center().x, 0.3, SUBURB_MAIN_Z))


func _house(lot_center: Vector3, side: float) -> void:
	var sidings := ["siding_beige", "siding_blue", "siding_white", "siding_yellow", "siding_grey"]
	var siding: String = sidings[rng.randi() % sidings.size()]
	b.box(Vector3(20.0, 0.08, 22.0), lot_center + Vector3(0, 0.04, 0), "grass", false)
	var house_center := lot_center + Vector3(side * 3.0, 0, 0)
	var size := Vector3(10.0, 5.6, 9.0)
	b.box(size, house_center + Vector3(0, size.y * 0.5, 0), siding)
	var roof := PrismMesh.new()
	roof.size = Vector3(size.x + 1.0, 3.2, size.z + 1.0)
	b.mesh(roof, Transform3D(Basis(), house_center + Vector3(0, size.y + 1.6, 0)), "shingles")
	b.collider_box(Vector3(size.x, 3.0, size.z), house_center + Vector3(0, size.y + 1.5, 0))
	# Driveway from the street, garage door, fence at the back
	var street_side := -side
	b.box(Vector3(9.0, 0.1, 4.0), lot_center + Vector3(street_side * 6.0, 0.06, 6.5), "concrete", false)
	b.box(Vector3(0.1, 2.4, 3.0), house_center + Vector3(street_side * (size.x * 0.5 + 0.02), 1.2, 2.5), "trim", false)
	b.box(Vector3(0.12, 1.1, 22.0), lot_center + Vector3(side * 9.9, 0.55, 0), "fence")
	if rng.randf() < 0.55:
		w.add_parked_car(lot_center + Vector3(street_side * 6.0, 0.4, 6.5), PI * 0.5)
	if rng.randf() < 0.6:
		w.add_tree(lot_center + Vector3(side * 7.0, 0, -7.0), rng.randf_range(0.8, 1.2), false)
	if rng.randf() < 0.3:
		w.add_region_point("suburb", lot_center + Vector3(street_side * 9.0, 0.3, 0))
