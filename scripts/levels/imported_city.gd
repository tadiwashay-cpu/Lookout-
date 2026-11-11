class_name ImportedCity
extends RefCounted
## The modelled city (assets/models/city, converted by tools/import_city.py):
## chunked meshes with vertex colours, box colliders for buildings and
## props, and road centrelines. Picks free roadside lots for the HQ, bank,
## precinct, pawn shop, the story market and parked cars, so gameplay never
## depends on hand-typed coordinates.

const SCENE := "res://assets/models/city/city.glb"
const DATA := "res://assets/models/city/city_data.json"
const LOT_OFFSET := 9.0      # roadside lots sit this far from a road centreline
const LOT_SPACING := 24.0

var w: World
var roads: Array = []        # [[Vector2, Vector2], ...]
var lots: Array = []         # [{"pos": Vector3, "yaw": float, "road": int}]
var bounds := Rect2()
var market := Vector3.ZERO
var pawn := Vector3.ZERO
var _boxes: Array = []       # [Rect2] footprints of the colliders
var _taken: Array[Vector3] = []
## The elevated highway along the north edge: its deck and ramps collide as
## real geometry (a box would wall off the road under it).
const HIGHWAY_Z0 := -164.0
const HIGHWAY_Z1 := -132.0
var buildings: Array = []    # [{"rect": Rect2, "height": float}] solid buildings
var lamps: Array[Vector3] = []          # street-light heads
var places: Dictionary = {}  # "repair"/"clinic"/"diner"/"gym" -> {"pos", "yaw", "along"}
var traffic_nodes: Array[Vector2] = []  # junctions of the main streets
var traffic_links: Array = []           # per node: Array[int] of neighbours
var _claimed: Array = []
var _material: ShaderMaterial
const CITY_SHADER := preload("res://assets/materials/shaders/city.gdshader")


static func available() -> bool:
	return ResourceLoader.exists(SCENE) and FileAccess.file_exists(DATA)


func _init(world: World) -> void:
	w = world


func build() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var b: Array = data["bounds"]
	bounds = Rect2(Vector2(b[0], b[1]), Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))).abs()
	var city := (load(SCENE) as PackedScene).instantiate() as Node3D
	city.name = "City"
	w.add_child(city)
	_material = ShaderMaterial.new()
	_material.shader = CITY_SHADER
	var deck_faces := PackedVector3Array()
	for node in city.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.visibility_range_end = maxf(GameSettings.view_distance * 1.6, 420.0)
		mesh.visibility_range_end_margin = 30.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, _material)
		# Highway deck, ramps and pillars: collide with the drawn triangles.
		var box := mesh.global_transform * mesh.get_aabb()
		if box.position.z < HIGHWAY_Z1 and box.end.z > HIGHWAY_Z0:
			var xf := mesh.global_transform
			var faces := mesh.mesh.get_faces()
			for f in range(0, faces.size(), 3):
				var p0 := xf * faces[f]
				var p1 := xf * faces[f + 1]
				var p2 := xf * faces[f + 2]
				var cz := (p0.z + p1.z + p2.z) / 3.0
				if cz > HIGHWAY_Z0 and cz < HIGHWAY_Z1 and maxf(p0.y, maxf(p1.y, p2.y)) > 0.25:
					deck_faces.append(p0)
					deck_faces.append(p1)
					deck_faces.append(p2)
	var raw_roads: Array = []
	for r: Array in data["roads"]:
		var a := Vector2(r[0][0], r[0][1])
		var e := Vector2(r[1][0], r[1][1])
		var length := a.distance_to(e)
		if length < 0.5:
			continue
		raw_roads.append([a, e])
		# Lane markings are mostly short dashes: stretch each one along its
		# direction so neighbours join into a continuous road line.
		if length < 12.0:
			var mid := (a + e) * 0.5
			var dir := (e - a) / length
			a = mid - dir * 7.0
			e = mid + dir * 7.0
		roads.append([a, e])
		w.map_lines.append(PackedVector2Array([a, e]))
	# Colliders: one static body, a box per building/prop. Nothing may stand on
	# a traffic lane: arches, light arms and canopies over the road are skipped.
	var body := StaticBody3D.new()
	body.name = "CityColliders"
	body.collision_layer = 1
	w.add_child(body)
	for c: Array in data["colliders"]:
		var size := Vector3(c[3], c[4], c[5])
		var rect := Rect2(float(c[0]) - size.x * 0.5, float(c[2]) - size.z * 0.5, size.x, size.z)
		if maxf(size.x, size.z) < 3.0 and size.y > 9.0:
			lamps.append(Vector3(c[0], float(c[1]) + size.y * 0.5 - 0.5, c[2]))
		if size.x * size.z > 4000.0:
			continue   # not a building: a sheet covering half the city
		if float(c[2]) > HIGHWAY_Z0 and float(c[2]) < HIGHWAY_Z1:
			continue   # highway parts use the triangle collider
		if _on_road(rect, raw_roads):
			continue
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(c[0], c[1], c[2])
		body.add_child(col)
		_boxes.append(rect)
		if size.x * size.z > 110.0 and size.y > 6.0:
			buildings.append({"rect": rect, "height": size.y})
	if deck_faces.size() >= 3:
		var deck := ConcavePolygonShape3D.new()
		deck.backface_collision = true
		deck.set_faces(deck_faces)
		var deck_col := CollisionShape3D.new()
		deck_col.shape = deck
		body.add_child(deck_col)
	_build_traffic_graph(raw_roads)
	_find_lots()
	_place_landmarks(data)


func _on_road(rect: Rect2, raw_roads: Array) -> bool:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for r: Array in raw_roads:
		var a: Vector2 = r[0]
		var e: Vector2 = r[1]
		if maxf(a.x, e.x) < rect.position.x or minf(a.x, e.x) > rect.end.x or maxf(a.y, e.y) < rect.position.y or minf(a.y, e.y) > rect.end.y:
			continue
		if rect.has_point(a) or rect.has_point(e):
			return true
		for k in 4:
			if Geometry2D.segment_intersects_segment(a, e, corners[k], corners[(k + 1) % 4]) != null:
				return true
	return false


## Street lights and windows come on at night (0 = day, 1 = night).
func set_night(amount: float) -> void:
	if _material:
		_material.set_shader_parameter("night", amount)


## Main streets: lane markings clustered into long straight axes; junctions
## where they cross become the nodes traffic drives between.
func _build_traffic_graph(raw_roads: Array) -> void:
	var lines := {true: [], false: []}   # horizontal? -> [[coord, lo, hi, length]]
	for r: Array in raw_roads:
		var a: Vector2 = r[0]
		var e: Vector2 = r[1]
		if (a.y + e.y) * 0.5 < HIGHWAY_Z1 + 4.0:
			continue
		var horizontal := absf(e.x - a.x) > absf(e.y - a.y)
		if horizontal:
			(lines[true] as Array).append([(a.y + e.y) * 0.5, minf(a.x, e.x), maxf(a.x, e.x), a.distance_to(e)])
		else:
			(lines[false] as Array).append([(a.x + e.x) * 0.5, minf(a.y, e.y), maxf(a.y, e.y), a.distance_to(e)])
	var axes := {true: [], false: []}    # [[coord, lo, hi]]
	for horizontal: bool in [true, false]:
		var list: Array = lines[horizontal]
		list.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var group: Array = []
		for k in list.size() + 1:
			if k == list.size() or (not group.is_empty() and float(list[k][0]) - float(group[group.size() - 1][0]) > 10.0):
				var total := 0.0
				var coord := 0.0
				var lo := INF
				var hi := -INF
				for g: Array in group:
					total += float(g[3])
					coord += float(g[0]) * float(g[3])
					lo = minf(lo, g[1])
					hi = maxf(hi, g[2])
				if total > 150.0:
					(axes[horizontal] as Array).append([coord / total, lo, hi])
				group = []
			if k < list.size():
				group.append(list[k])
	var on_axis := {}   # "h0"/"v2" -> [[position along the axis, node index]]
	for hi_i in (axes[true] as Array).size():
		var h: Array = axes[true][hi_i]
		for vi in (axes[false] as Array).size():
			var v: Array = axes[false][vi]
			if float(v[0]) > float(h[1]) - 16.0 and float(v[0]) < float(h[2]) + 16.0 and float(h[0]) > float(v[1]) - 16.0 and float(h[0]) < float(v[2]) + 16.0:
				var index := traffic_nodes.size()
				traffic_nodes.append(Vector2(v[0], h[0]))
				traffic_links.append([])
				for key: String in ["h%d" % hi_i, "v%d" % vi]:
					if not on_axis.has(key):
						on_axis[key] = []
					(on_axis[key] as Array).append([float(v[0]) if key.begins_with("h") else float(h[0]), index])
	for key: String in on_axis:
		var along: Array = on_axis[key]
		along.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		for k in along.size() - 1:
			(traffic_links[along[k][1]] as Array).append(along[k + 1][1])
			(traffic_links[along[k + 1][1]] as Array).append(along[k][1])


## True when a disc at `p` touches no building footprint.
func is_free(p: Vector2, radius: float) -> bool:
	if not bounds.grow(-radius).has_point(p):
		return false
	for box: Rect2 in _boxes:
		if box.grow(radius).has_point(p):
			return false
	return true


func _find_lots() -> void:
	for i in roads.size():
		var a: Vector2 = roads[i][0]
		var e: Vector2 = roads[i][1]
		var along := (e - a).normalized()
		var normal := Vector2(-along.y, along.x)
		var d := minf(LOT_SPACING * 0.5, a.distance_to(e) * 0.5)
		if a.distance_to(e) < LOT_SPACING and (i % 3) != 0:
			continue   # dashes are dense: sample every third one
		while d < a.distance_to(e) - 2.0:
			for side: float in [-1.0, 1.0]:
				var p := a + along * d + normal * side * LOT_OFFSET
				if p.y > HIGHWAY_Z1 + 6.0 and is_free(p, 3.2) and _clear_of_roads(p, i):
					# face the road
					var face := -normal * side
					lots.append({"pos": Vector3(p.x, 0.05, p.y), "yaw": atan2(-face.x, -face.y), "road": i,
						"along": Vector3(along.x, 0.0, along.y)})
			d += LOT_SPACING


## Lots must not sit on another road.
func _clear_of_roads(p: Vector2, own: int) -> bool:
	for i in roads.size():
		if i == own:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(p, roads[i][0], roads[i][1])
		if closest.distance_to(p) < 6.0:
			return false
	return true


func _take(near: Vector2, min_gap: float, free_radius: float = 3.2) -> Dictionary:
	var best := {}
	var best_d := INF
	for lot: Dictionary in lots:
		var pos: Vector3 = lot["pos"]
		var ok := is_free(Vector2(pos.x, pos.z), free_radius)
		for t in _taken:
			if t.distance_to(pos) < min_gap:
				ok = false
		if not ok:
			continue
		var d := Vector2(pos.x, pos.z).distance_to(near)
		if d < best_d:
			best_d = d
			best = lot
	if best.is_empty() and not lots.is_empty():
		best = lots[0]
	if not best.is_empty():
		_taken.append(best["pos"])
	return best


## Picks a real building near `near` and returns its street door:
## {"pos", "yaw", "along", "height", "face"}. Falls back to a roadside lot.
func _claim(near: Vector2, min_area: float, max_area: float = 1.0e9) -> Dictionary:
	var order := buildings.duplicate()
	order.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return (p["rect"] as Rect2).get_center().distance_to(near) < (q["rect"] as Rect2).get_center().distance_to(near))
	for b: Dictionary in order:
		var rect: Rect2 = b["rect"]
		if _claimed.has(b) or rect.get_area() < min_area or rect.get_area() > max_area:
			continue
		var c := rect.get_center()
		var best := Vector2.ZERO
		var best_d := INF
		for r: Array in roads:
			if (r[0] as Vector2).y < HIGHWAY_Z1 + 6.0:
				continue
			var q := Geometry2D.get_closest_point_to_segment(c, r[0], r[1])
			if q.distance_to(c) < best_d:
				best_d = q.distance_to(c)
				best = q
		if best_d > 60.0:
			continue
		var to_road := best - c
		var face := Vector2(signf(to_road.x), 0.0) if absf(to_road.x) / rect.size.x > absf(to_road.y) / rect.size.y else Vector2(0.0, signf(to_road.y))
		var door := c + face * (absf(face.x) * rect.size.x * 0.5 + absf(face.y) * rect.size.y * 0.5 + 2.4)
		if not is_free(door, 1.3):
			continue
		_claimed.append(b)
		var pos := Vector3(door.x, 0.05, door.y)
		_taken.append(pos)
		return {"pos": pos, "yaw": atan2(-face.x, -face.y), "along": Vector3(-face.y, 0.0, face.x), "height": b["height"], "face": Vector3(face.x, 0.0, face.y)}
	var lot := _take(near, 30.0)
	lot["height"] = 6.0
	lot["face"] = Vector3.ZERO
	return lot


func _sign(spot: Dictionary, text: String, color: Color, size: int = 64) -> void:
	var pos: Vector3 = spot["pos"]
	w.add_label(text, pos + Vector3.UP * minf(float(spot["height"]) * 0.6, 7.0) - (spot["face"] as Vector3) * 1.2, size, color)
	w.map_places.append({"pos": pos, "text": text, "color": color})


func _place_landmarks(data: Dictionary) -> void:
	if lots.is_empty():
		push_warning("ImportedCity: no free roadside lots found")
		return
	var c := bounds.get_center()
	var towers: Array = data.get("towers", [])
	var tall := c
	if not towers.is_empty():
		tall = Vector2(towers[0]["pos"][0], towers[0]["pos"][2])
	# Every landmark is a real building of the city; you use its street door.
	var bank := _claim(tall, 110.0)
	var hq := _claim(c + Vector2(-bounds.size.x * 0.1, -bounds.size.y * 0.05), 150.0, 700.0)
	var precinct := _claim(c + Vector2(bounds.size.x * 0.25, -bounds.size.y * 0.1), 200.0)
	var pawn_lot := _claim(c + Vector2(bounds.size.x * 0.05, -bounds.size.y * 0.2), 110.0, 500.0)
	var market_lot := _take(c + Vector2(0.0, bounds.size.y * 0.12), 60.0, 7.0)
	w.bank_position = bank["pos"]
	w.hq_spawn = (hq["pos"] as Vector3) + Vector3.UP * 0.3
	w.hq_garage = (hq["pos"] as Vector3) + (hq["along"] as Vector3) * 7.0 + (hq["face"] as Vector3) * 2.5 + Vector3.UP * 0.4
	w.precinct_position = (precinct["pos"] as Vector3) + (precinct["face"] as Vector3) * 3.0 + Vector3.UP * 0.3
	pawn = pawn_lot["pos"]
	market = market_lot["pos"]
	_sign(bank, "FIRST HARBOR BANK", Color(0.9, 0.85, 0.7), 72)
	_sign(hq, "HQ", Color(1.0, 0.75, 0.3), 72)
	_sign(precinct, "84TH PRECINCT", Color(0.75, 0.85, 1.0))
	w.map_places.append({"pos": pawn, "text": "PAWN SHOP", "color": Color(1.0, 0.55, 0.15)})
	places["repair"] = _claim(c + Vector2(-bounds.size.x * 0.05, bounds.size.y * 0.3), 150.0)
	places["clinic"] = _claim(c + Vector2(bounds.size.x * 0.12, bounds.size.y * 0.05), 110.0, 700.0)
	places["diner"] = _claim(c + Vector2(bounds.size.x * 0.2, -bounds.size.y * 0.25), 110.0, 500.0)
	places["gym"] = _claim(c + Vector2(bounds.size.x * 0.3, bounds.size.y * 0.2), 110.0, 900.0)


## Points along the roads (police spawns, traffic).
func road_points(step: float = 22.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r: Array in roads:
		var a: Vector2 = r[0]
		var e: Vector2 = r[1]
		var n := maxi(int(a.distance_to(e) / step), 1)
		for i in n + 1:
			var p := a.lerp(e, float(i) / n)
			out.append(Vector3(p.x, 0.3, p.y))
	return out


## Roadside spots for parked cars (lots not used by landmarks).
func parking(count: int, rng: RandomNumberGenerator) -> Array:
	var free: Array = []
	for lot: Dictionary in lots:
		var pos: Vector3 = lot["pos"]
		var near_landmark := false
		for t in _taken:
			if t.distance_to(pos) < 14.0:
				near_landmark = true
		if not near_landmark:
			free.append(lot)
	var out: Array = []
	var step := maxi(free.size() / maxi(count, 1), 1)
	var i := rng.randi() % step
	while i < free.size() and out.size() < count:
		out.append(free[i])
		i += step
	return out


## A free roadside spot at least `far` metres from `from` (goon squads...).
func spot_away_from(from: Vector3, far: float, rng: RandomNumberGenerator) -> Vector3:
	for attempt in 40:
		var lot: Dictionary = lots[rng.randi() % lots.size()]
		var pos: Vector3 = lot["pos"]
		if pos.distance_to(from) > far:
			return pos
	return lots[rng.randi() % lots.size()]["pos"]
