class_name NfsHud
extends Control
## Street-racer style HUD (replaces the heat stars):
##  * top-right PURSUIT panel: HEAT level 1-5, and a meter that is red
##    while the cops can see you and turns into a blue EVADE / COOLDOWN
##    bar as you get away
##  * bottom-right tachometer when driving: rev arc, needle, gear and
##    digital km/h
## Everything is drawn in _draw (no extra nodes, cheap on mobile).

const GEAR_TOPS := [0.0, 12.0, 22.0, 33.0, 45.0, 58.0, 80.0]   # m/s where each gear tops out

var player: PlayerController
var _font: Font = UITheme.HUD_FONT
var _blink := 0.0
var _rpm := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_blink += delta
	if player and player.current_vehicle:
		var speed := absf(player.current_vehicle.forward_speed())
		var gear := _gear_for(speed)
		var low: float = GEAR_TOPS[gear - 1]
		var high: float = GEAR_TOPS[gear]
		var target := clampf((speed - low) / maxf(high - low, 1.0), 0.0, 1.0) * 0.82 + 0.15
		_rpm = lerpf(_rpm, target, clampf(delta * 8.0, 0.0, 1.0))
	queue_redraw()


func _gear_for(speed: float) -> int:
	for g in range(1, GEAR_TOPS.size()):
		if speed < GEAR_TOPS[g]:
			return g
	return GEAR_TOPS.size() - 1


func _draw() -> void:
	if player == null:
		return
	if Session.mode == Session.MODE_STORY and WantedSystem.stars > 0:
		_draw_pursuit()
	if player.current_vehicle:
		_draw_tacho(player.current_vehicle)


func _draw_pursuit() -> void:
	var w := 420.0
	var origin := Vector2((size.x - w) * 0.5, 116.0)   # top centre under the status line, clear of ammo/gear text
	draw_rect(Rect2(origin, Vector2(w, 92)), Color(0, 0, 0, 0.55))
	var seen := WantedSystem.is_seen()
	var title := "PURSUIT" if seen else "EVADE"
	var accent := Color(1.0, 0.18, 0.12) if seen else Color(0.3, 0.6, 1.0)
	if seen and fmod(_blink, 0.6) < 0.3:
		accent = Color(0.3, 0.45, 1.0)   # red/blue flash like a light bar
	draw_string(_font, origin + Vector2(16, 38), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, accent)
	draw_string(_font, origin + Vector2(w - 16, 38), "HEAT %d" % WantedSystem.stars, HORIZONTAL_ALIGNMENT_RIGHT, -1, 30, Color(1, 0.85, 0.4))
	# Heat segments
	for i in WantedSystem.MAX_STARS:
		var seg := Rect2(origin + Vector2(16 + i * 80.0, 50), Vector2(72, 10))
		draw_rect(seg, Color(1, 0.75, 0.2) if i < WantedSystem.stars else Color(1, 1, 1, 0.15))
	# Pursuit / cooldown meter
	var bar := Rect2(origin + Vector2(16, 68), Vector2(w - 32, 12))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var fill := 1.0 if seen else WantedSystem.evade_progress()
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), accent)


func _draw_tacho(car: DrivableCar) -> void:
	var radius := 120.0
	var center := Vector2(size.x - radius - 50.0, size.y - radius - 40.0)
	draw_circle(center, radius + 14.0, Color(0, 0, 0, 0.55))
	var start := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)
	draw_arc(center, radius, start, start + sweep, 48, Color(1, 1, 1, 0.25), 6.0)
	draw_arc(center, radius, start + sweep * 0.8, start + sweep, 12, Color(1, 0.2, 0.15, 0.8), 6.0)   # redline
	draw_arc(center, radius, start, start + sweep * _rpm, 48, Color(1, 0.62, 0.2), 10.0)
	# Nitro: inner blue arc, bright while burning.
	draw_arc(center, radius - 22.0, start, start + sweep, 32, Color(1, 1, 1, 0.1), 6.0)
	draw_arc(center, radius - 22.0, start, start + sweep * car.nitro, 32, Color(0.5, 0.9, 1.0) if car.nitro_on else Color(0.25, 0.6, 1.0), 6.0)
	for i in 9:
		var a := start + sweep * i / 8.0
		draw_line(center + Vector2.from_angle(a) * (radius - 18), center + Vector2.from_angle(a) * (radius - 4), Color(1, 1, 1, 0.7), 3.0)
	var needle := start + sweep * _rpm
	draw_line(center, center + Vector2.from_angle(needle) * (radius - 10), Color(1, 0.3, 0.2), 4.0)
	draw_circle(center, 8.0, Color(1, 0.3, 0.2))
	var speed := absf(car.forward_speed())
	var kmh := roundi(speed * 3.6)
	draw_string(_font, center + Vector2(-radius, 40), "%d" % kmh, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 58, Color(0.95, 0.93, 0.88))
	draw_string(_font, center + Vector2(-radius, 72), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 20, Color(1, 1, 1, 0.6))
	var gear := "R" if car.forward_speed() < -0.5 else ("N" if speed < 0.5 else str(_gear_for(speed)))
	draw_string(_font, center + Vector2(-30, -26), gear, HORIZONTAL_ALIGNMENT_CENTER, 60, 44, Color(1, 0.75, 0.3))
