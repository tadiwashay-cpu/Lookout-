class_name WantedStars
extends Control
## Draws the police heat level as five stars (filled = active).

var stars: int = 0:
	set(value):
		stars = value
		queue_redraw()

var _flash := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 56)
	WantedSystem.stars_changed.connect(_on_stars_changed)
	stars = WantedSystem.stars


func _on_stars_changed(value: int) -> void:
	stars = value
	_flash = 1.0


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 0.8, 0.0)
		queue_redraw()


func _draw() -> void:
	var radius := 24.0
	var spacing := 58.0
	var start_x := size.x - radius - (WantedSystem.MAX_STARS - 1) * spacing
	for i in WantedSystem.MAX_STARS:
		var center := Vector2(start_x + i * spacing, size.y * 0.5)
		var points := _star_points(center, radius)
		if i < stars:
			var blink := 0.75 + 0.25 * sin(_flash * 25.0)
			draw_colored_polygon(points, Color(0.96, 0.93, 0.86, blink))
		else:
			draw_colored_polygon(points, Color(0.0, 0.0, 0.0, 0.35))
		points.append(points[0])
		draw_polyline(points, Color(0.96, 0.93, 0.86, 0.8), 2.0, true)


func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points
