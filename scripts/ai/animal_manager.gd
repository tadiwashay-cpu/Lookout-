class_name AnimalManager
extends Node
## Keeps a handful of animals around the player while they are in the forest.

const MAX_ANIMALS := 9

var world: World
var _animals: Array[Animal] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or world.player == null:
		return
	_timer = 1.2
	var p := world.player
	var focus := p.current_vehicle.global_position if p.current_vehicle else p.global_position
	var alive: Array[Animal] = []
	for animal in _animals:
		if is_instance_valid(animal):
			if animal.global_position.distance_to(focus) > 190.0:
				animal.queue_free()
			else:
				alive.append(animal)
	_animals = alive
	if _animals.size() >= MAX_ANIMALS or not WorldRegions.FOREST_RECT.grow(60.0).has_point(Vector2(focus.x, focus.z)):
		return
	for attempt in 5:
		var angle := _rng.randf() * TAU
		var spot := focus + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(55.0, 120.0)
		if not WorldRegions.FOREST_RECT.grow(-15.0).has_point(Vector2(spot.x, spot.z)):
			continue
		var roll := _rng.randf()
		var kind := "deer" if roll < 0.45 else ("rabbit" if roll < 0.8 else "fox")
		for i in (_rng.randi_range(2, 4) if kind == "deer" else 1):   # deer come in small herds
			var animal := Animal.new()
			animal.world = world
			animal.kind = kind
			var at := spot + Vector3(_rng.randf_range(-5, 5), 0.0, _rng.randf_range(-5, 5))
			animal.position = Vector3(at.x, world.ground_height(at.x, at.z), at.z)
			world.add_child(animal)
			_animals.append(animal)
		return
