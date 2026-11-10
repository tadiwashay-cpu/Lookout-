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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	if _bounds.size == Vector2.ZERO:
		_compute_bounds()
	visible = true
	add_to_group(&"full_map_open")
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		visible = false
		remove_from_group(&"full_map_open")
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
