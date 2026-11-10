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
	for node in city.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.visibility_range_end = maxf(GameSettings.view_distance * 1.6, 420.0)
		mesh.visibility_range_end_margin = 30.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	# Colliders: one static body, a box per building/prop.
	var body := StaticBody3D.new()
	body.name = "CityColliders"
	body.collision_layer = 1
	w.add_child(body)
	for c: Array in data["colliders"]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(c[3], c[4], c[5])
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(c[0], c[1], c[2])
		body.add_child(col)
		_boxes.append(Rect2(float(c[0]) - float(c[3]) * 0.5, float(c[2]) - float(c[5]) * 0.5, c[3], c[5]))
	for r: Array in data["roads"]:
		var a := Vector2(r[0][0], r[0][1])
		var e := Vector2(r[1][0], r[1][1])
		# Lane markings are mostly short dashes: stretch each one along its
		# direction so neighbours join into a continuous road line.
		var length := a.distance_to(e)
		if length < 0.5:
			continue
		if length < 12.0:
			var mid := (a + e) * 0.5
			var dir := (e - a) / length
			a = mid - dir * 7.0
			e = mid + dir * 7.0
		roads.append([a, e])
		w.map_lines.append(PackedVector2Array([a, e]))
	_find_lots()
	_place_landmarks(data)


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
				if is_free(p, 3.2) and _clear_of_roads(p, i):
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


func _place_landmarks(data: Dictionary) -> void:
	if lots.is_empty():
		push_warning("ImportedCity: no free roadside lots found")
		return
	var c := bounds.get_center()
	var towers: Array = data.get("towers", [])
	var tall := c
	if not towers.is_empty():
		tall = Vector2(towers[0]["pos"][0], towers[0]["pos"][2])
	# Bank: by the tallest building. HQ: west side. Precinct: east side.
	var bank := _take(tall, 0.0)
	var hq := _take(c + Vector2(-bounds.size.x * 0.12, bounds.size.y * 0.05), 70.0, 5.0)
	var precinct := _take(c + Vector2(bounds.size.x * 0.25, -bounds.size.y * 0.1), 70.0, 5.0)
	var pawn_lot := _take(c + Vector2(bounds.size.x * 0.05, -bounds.size.y * 0.2), 50.0)
	var market_lot := _take(c, 60.0, 7.0)
	w.bank_position = bank["pos"]
	w.hq_spawn = (hq["pos"] as Vector3) + Vector3.UP * 0.3
	w.hq_garage = (hq["pos"] as Vector3) + (hq["along"] as Vector3) * 7.0 + Vector3.UP * 0.4
	w.precinct_position = (precinct["pos"] as Vector3) + Vector3.UP * 0.3
	pawn = pawn_lot["pos"]
	market = market_lot["pos"]
	w.add_label("FIRST HARBOR BANK", (bank["pos"] as Vector3) + Vector3.UP * 5.0, 72, Color(0.9, 0.85, 0.7))
	w.add_label("HQ", (hq["pos"] as Vector3) + Vector3.UP * 4.0, 72, Color(1.0, 0.75, 0.3))
	w.add_label("84TH PRECINCT", (precinct["pos"] as Vector3) + Vector3.UP * 5.0, 64, Color(0.75, 0.85, 1.0))


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
