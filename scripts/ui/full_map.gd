class_name FullMap
extends Control
## Full-screen map, opened by tapping the minimap. North is up, the whole
## world fits on screen: roads, water, forest, region names, you, the
## mode's objectives and (when wanted) the police. Tap anywhere to close.

var world: World
var player: PlayerController
var _bounds := Rect2()
var _font: Font = UITheme.HUD_FONT


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


var _changed_at := 0


## One tap can arrive twice (touch + emulated mouse): ignore the echo.
func toggle() -> void:
	if Time.get_ticks_msec() - _changed_at < 350:
		return
	_changed_at = Time.get_ticks_msec()
	if visible:
		visible = false
		remove_from_group(&"full_map_open")
		return
	_compute_bounds()
	position = Vector2.ZERO
	size = get_viewport_rect().size   # always the whole screen
	visible = true
	add_to_group(&"full_map_open")
	queue_redraw()


func open() -> void:
	if not visible:
		toggle()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		if visible:
			toggle()
		accept_event()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _compute_bounds() -> void:
	var first := true
	for line in world.map_lines:
		for p: Vector2 in line:
			if first:
				_bounds = Rect2(p, Vector2.ZERO)
				first = false
			else:
				_bounds = _bounds.expand(p)
	for r: Rect2 in [world.map_water, world.map_forest]:
		if r.size != Vector2.ZERO:
			_bounds = _bounds.merge(r)
	_bounds = _bounds.merge(World.MAP_BOUNDS)   # the whole world, not just where roads are
	_bounds = _bounds.grow(60.0)


func _to_screen(x: float, z: float) -> Vector2:
	var area := Rect2(Vector2(60, 60), size - Vector2(120, 120))
	var s := minf(area.size.x / _bounds.size.x, area.size.y / _bounds.size.y)
	var offset := area.position + (area.size - _bounds.size * s) * 0.5
	return offset + (Vector2(x, z) - _bounds.position) * s


func _draw() -> void:
	if world == null or player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.06, 0.96))
	for pair in [[world.map_water, Color(0.15, 0.25, 0.32)], [world.map_forest, Color(0.15, 0.24, 0.14)]]:
		var r: Rect2 = pair[0]
		if r.size != Vector2.ZERO:
			var a := _to_screen(r.position.x, r.position.y)
			var b := _to_screen(r.end.x, r.end.y)
			draw_rect(Rect2(a, b - a), pair[1])
	# Land, then the forest and water on top of it.
	var land_a := _to_screen(World.MAP_BOUNDS.position.x, World.MAP_BOUNDS.position.y)
	var land_b := _to_screen(World.MAP_BOUNDS.end.x, World.MAP_BOUNDS.end.y)
	draw_rect(Rect2(land_a, land_b - land_a), Color(0.16, 0.2, 0.15))
	for pair in [[world.map_water, Color(0.15, 0.27, 0.38)], [world.map_forest, Color(0.1, 0.24, 0.12)], [WorldRegions.SUBURB_RECT, Color(0.24, 0.23, 0.2)]]:
		var r: Rect2 = pair[0]
		if r.size != Vector2.ZERO:
			var a := _to_screen(r.position.x, r.position.y)
			var b := _to_screen(r.end.x, r.end.y)
			draw_rect(Rect2(a, b - a), pair[1])
	if world.imported_city:
		var ca := _to_screen(world.imported_city.bounds.position.x, world.imported_city.bounds.position.y)
		var cb := _to_screen(world.imported_city.bounds.end.x, world.imported_city.bounds.end.y)
		draw_rect(Rect2(ca, cb - ca), Color(0.2, 0.2, 0.22))
		for building: Dictionary in world.imported_city.buildings:
			var r: Rect2 = building["rect"]
			var a := _to_screen(r.position.x, r.position.y)
			draw_rect(Rect2(a, _to_screen(r.end.x, r.end.y) - a), Color(0.36, 0.36, 0.4))
	for line in world.map_lines:
		var pts := PackedVector2Array()
		for p: Vector2 in line:
			pts.append(_to_screen(p.x, p.y))
		if pts.size() > 1:
			draw_polyline(pts, Color(0.62, 0.62, 0.6), 2.5)
	for region: String in world.region_points:
		var points: Array = world.region_points[region]
		if points.is_empty():
			continue
		var c := Vector3.ZERO
		for p: Vector3 in points:
			c += p
		c /= points.size()
		draw_string(_font, _to_screen(c.x, c.z), region.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(1, 1, 1, 0.55))
	for place: Dictionary in world.map_places:
		var pp: Vector3 = place["pos"]
		var sp := _to_screen(pp.x, pp.z)
		draw_circle(sp, 6.0, place["color"])
		draw_arc(sp, 6.0, 0.0, TAU, 12, Color(0, 0, 0, 0.8), 1.5)
	# Legend: the places, by colour, down the right-hand side.
	var row := 0
	for place: Dictionary in world.map_places:
		var at := Vector2(size.x - 330.0, 120.0 + row * 34.0)
		draw_circle(at + Vector2(0, -8), 9.0, place["color"])
		draw_string(_font, at + Vector2(22, 0), str(place["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.92))
		row += 1
	if world.mode:
		for marker: Dictionary in world.mode.minimap_markers():
			var mp: Vector3 = marker["pos"]
			var sp := _to_screen(mp.x, mp.z)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -10), sp + Vector2(10, 0), sp + Vector2(0, 10), sp + Vector2(-10, 0)]), marker["color"])
	if WantedSystem.stars > 0:
		for node in get_tree().get_nodes_in_group(&"police"):
			var pp := (node as Node3D).global_position
			draw_circle(_to_screen(pp.x, pp.z), 6.0, Color(0.35, 0.6, 1.0))
	var me := player.current_vehicle.global_position if player.current_vehicle else player.global_position
	var forward := player.current_vehicle.global_basis.z if player.current_vehicle else -player.global_basis.z
	var heading := atan2(forward.x, -forward.z)
	var c2 := _to_screen(me.x, me.z)
	draw_colored_polygon(PackedVector2Array([c2 + Vector2(0, -16).rotated(heading), c2 + Vector2(10, 12).rotated(heading), c2 + Vector2(-10, 12).rotated(heading)]), Color(1, 0.75, 0.25))
	draw_string(_font, Vector2(0, 50), "MAP  —  tap to close", HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color(0.95, 0.93, 0.88))
