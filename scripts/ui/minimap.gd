class_name Minimap
extends Control
## Circular radar, rotated so "up" is where the camera looks.
##  roads (grey), water (blue), forest (green), you (white arrow),
##  danger (red: goons, hostile players), police/allies (blue),
##  objectives (gold), battle-royale safe zone (white ring).
## Danger beyond the edge is pinned to the rim so you know where it is.

const RADIUS_PX := 120.0
const RANGE_M := 180.0
const DANGER_RANGE_M := 400.0

var world: World
var player: PlayerController
var _pulse := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS_PX * 2.0 + 8.0, RADIUS_PX * 2.0 + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _focus() -> Vector3:
	if player.current_vehicle:
		return player.current_vehicle.global_position
	return player.global_position


## World (x, z) -> minimap pixels, rotated by the camera yaw.
func _to_map(world_pos: Vector3, center: Vector2, origin: Vector3, yaw: float) -> Vector2:
	var offset := Vector2(world_pos.x - origin.x, world_pos.z - origin.z)
	var rotated := offset.rotated(yaw)
	return center + rotated * (RADIUS_PX / RANGE_M)


func _draw() -> void:
	if world == null or player == null:
		return
	var center := size * 0.5
	var origin := _focus()
	var yaw := player.view_yaw()
	draw_circle(center, RADIUS_PX + 4.0, Color(0.0, 0.0, 0.0, 0.55))
	draw_circle(center, RADIUS_PX, Color(0.13, 0.14, 0.15, 0.85))

	# Areas: water and forest (sampled as clipped dots for a cheap fill)
	_draw_rect_area(world.map_water, Color(0.15, 0.25, 0.32, 0.9), center, origin, yaw)
	_draw_rect_area(world.map_forest, Color(0.15, 0.24, 0.14, 0.9), center, origin, yaw)

	# Roads
	for line in world.map_lines:
		for i in line.size() - 1:
			_clipped_segment(Vector3(line[i].x, 0, line[i].y), Vector3(line[i + 1].x, 0, line[i + 1].y), center, origin, yaw, Color(0.55, 0.55, 0.55, 0.9), 3.0)

	# Safe zone (battle royale)
	if world.mode:
		var zone := world.mode.safe_zone()
		if not zone.is_empty():
			var zc: Vector2 = zone["center"]
			var zr: float = zone["radius"]
			var zpos := _to_map(Vector3(zc.x, 0, zc.y), center, origin, yaw)
			var zr_px := zr * RADIUS_PX / RANGE_M
			if zpos.distance_to(center) - zr_px < RADIUS_PX:
				draw_arc(zpos, zr_px, 0.0, TAU, 96, Color(1, 1, 1, 0.85), 2.5, true)

	# Danger and others
	for node in get_tree().get_nodes_in_group(&"enemies"):
		_blip((node as Node3D).global_position, Color(1.0, 0.25, 0.2), center, origin, yaw, true)
	for avatar in world.remote_avatars():
		var a := avatar as RemoteAvatar
		if not a.is_alive() and not a.is_in_vehicle():
			continue
		var hostile := Session.mode != Session.MODE_HEIST or a.team != Session.team_of(Session.my_id())
		_blip(a.global_position, Color(1.0, 0.25, 0.2) if hostile else Color(0.4, 0.65, 1.0), center, origin, yaw, hostile)
	if WantedSystem.stars > 0:
		for node in get_tree().get_nodes_in_group(&"police"):
			_blip((node as Node3D).global_position, Color(0.35, 0.6, 1.0), center, origin, yaw, true)
	if world.mode:
		for marker: Dictionary in world.mode.minimap_markers():
			_marker(marker["pos"], marker["color"], center, origin, yaw)

	# You: arrow pointing up (camera-relative), car heading if driving
	var heading := 0.0
	if player.current_vehicle:
		var f := player.current_vehicle.global_basis.z   # car bodies drive +Z
		var on_map := Vector2(f.x, f.z).rotated(yaw)
		heading = atan2(on_map.x, -on_map.y)
	var tip := center + Vector2(0, -11).rotated(heading)
	var left := center + Vector2(-7, 8).rotated(heading)
	var right := center + Vector2(7, 8).rotated(heading)
	draw_colored_polygon(PackedVector2Array([tip, right, left]), Color(1, 1, 1))
	draw_arc(center, RADIUS_PX, 0.0, TAU, 64, Color(0.9, 0.88, 0.82, 0.8), 2.0, true)
	# North marker
	var north := center + (Vector2(0, -RADIUS_PX + 12.0)).rotated(yaw)
	draw_string(get_theme_default_font(), north - Vector2(5, -6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.88, 0.82))


func _blip(pos: Vector3, color: Color, center: Vector2, origin: Vector3, yaw: float, danger: bool) -> void:
	var dist := Vector2(pos.x - origin.x, pos.z - origin.z).length()
	if dist > DANGER_RANGE_M:
		return
	var p := _to_map(pos, center, origin, yaw)
	var offset := p - center
	if offset.length() > RADIUS_PX - 6.0:
		# Off the edge: pin to the rim as a pulsing wedge so you know the direction.
		var edge := center + offset.normalized() * (RADIUS_PX - 6.0)
		var pulse := 0.6 + 0.4 * sin(_pulse * 8.0)
		draw_circle(edge, 5.0, Color(color, pulse))
		return
	draw_circle(p, 4.5, color)
	if danger:
		var ring := fmod(_pulse * 1.5, 1.0)
		draw_arc(p, 4.5 + ring * 10.0, 0.0, TAU, 16, Color(color, 0.6 * (1.0 - ring)), 1.5, true)


func _marker(pos: Vector3, color: Color, center: Vector2, origin: Vector3, yaw: float) -> void:
	var p := _to_map(pos, center, origin, yaw)
	var offset := p - center
	if offset.length() > RADIUS_PX - 8.0:
		p = center + offset.normalized() * (RADIUS_PX - 8.0)
	var s := 7.0
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), color)


## Draws a segment clipped to the circle (sampled — cheap and good enough).
func _clipped_segment(a: Vector3, b: Vector3, center: Vector2, origin: Vector3, yaw: float, color: Color, width: float) -> void:
	var pa := _to_map(a, center, origin, yaw)
	var pb := _to_map(b, center, origin, yaw)
	var length := pa.distance_to(pb)
	if length < 0.5:
		return
	# Quick reject: segment entirely far outside
	var closest := Geometry2D.get_closest_point_to_segment(center, pa, pb)
	if closest.distance_to(center) > RADIUS_PX:
		return
	var steps := maxi(int(length / 6.0), 1)
	var start := Vector2.INF
	for i in steps + 1:
		var p := pa.lerp(pb, float(i) / steps)
		var inside := p.distance_to(center) <= RADIUS_PX - 1.0
		if inside and start == Vector2.INF:
			start = p
		elif not inside and start != Vector2.INF:
			draw_line(start, p, color, width)
			start = Vector2.INF
	if start != Vector2.INF:
		draw_line(start, pb, color, width)


func _draw_rect_area(rect: Rect2, color: Color, center: Vector2, origin: Vector3, yaw: float) -> void:
	if rect.size == Vector2.ZERO:
		return
	var view := Rect2(origin.x - RANGE_M, origin.z - RANGE_M, RANGE_M * 2.0, RANGE_M * 2.0)
	if not rect.intersects(view):
		return
	var area := rect.intersection(view)
	var corners := [
		Vector3(area.position.x, 0, area.position.y), Vector3(area.end.x, 0, area.position.y),
		Vector3(area.end.x, 0, area.end.y), Vector3(area.position.x, 0, area.end.y),
	]
	var poly := PackedVector2Array()
	for c: Vector3 in corners:
		var p := _to_map(c, center, origin, yaw)
		var offset := p - center
		if offset.length() > RADIUS_PX:
			p = center + offset.normalized() * RADIUS_PX
		poly.append(p)
	draw_colored_polygon(poly, color)
