class_name Animal
extends Node3D
## Forest wildlife (deer, fox, rabbit) built from a few boxes: grazes, wanders
## and bolts when the player or a car gets close. No physics body: it follows
## the terrain height, so a whole herd costs almost nothing.

const KINDS := {
	"deer": {"body": Vector3(0.42, 0.5, 1.15), "leg": 0.75, "neck": 0.55, "head": Vector3(0.2, 0.22, 0.42), "color": Color(0.55, 0.38, 0.22), "walk": 1.3, "run": 10.5, "scare": 26.0},
	"fox": {"body": Vector3(0.24, 0.24, 0.7), "leg": 0.3, "neck": 0.12, "head": Vector3(0.17, 0.16, 0.26), "color": Color(0.8, 0.4, 0.14), "walk": 1.5, "run": 8.5, "scare": 16.0},
	"rabbit": {"body": Vector3(0.16, 0.18, 0.3), "leg": 0.12, "neck": 0.05, "head": Vector3(0.12, 0.12, 0.14), "color": Color(0.62, 0.56, 0.5), "walk": 1.0, "run": 7.0, "scare": 11.0},
}

var world: World
var kind := "deer"
var _legs: Array[Node3D] = []
var _head: Node3D
var _spec: Dictionary
var _heading := 0.0
var _speed := 0.0
var _state_time := 0.0
var _fleeing := false
var _stride := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_spec = KINDS[kind]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _spec["color"]
	mat.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = (_spec["color"] as Color).darkened(0.35)
	dark.roughness = 0.9
	var body: Vector3 = _spec["body"]
	var leg: float = _spec["leg"]
	_part(self, body, Vector3(0, leg + body.y * 0.5, 0), mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3(sx * body.x * 0.36, leg, sz * body.z * 0.4)
			add_child(hip)
			_part(hip, Vector3(body.x * 0.24, leg, body.x * 0.24), Vector3(0, -leg * 0.5, 0), dark)
			_legs.append(hip)
	_head = Node3D.new()
	_head.position = Vector3(0, leg + body.y * 0.8, body.z * 0.5)
	add_child(_head)
	var neck: float = _spec["neck"]
	var head: Vector3 = _spec["head"]
	_part(_head, Vector3(body.x * 0.45, neck + 0.1, body.x * 0.45), Vector3(0, neck * 0.5, 0.02), mat)
	_part(_head, head, Vector3(0, neck + head.y * 0.4, head.z * 0.3), mat)
	for sx in [-1.0, 1.0]:   # ears (long for the rabbit, antler stubs for the deer)
		var ear := 0.2 if kind == "rabbit" else (0.3 if kind == "deer" else 0.1)
		_part(_head, Vector3(0.04, ear, 0.05), Vector3(sx * head.x * 0.35, neck + head.y * 0.8 + ear * 0.5, 0), dark)
	_part(self, Vector3(0.08, 0.1, 0.12), Vector3(0, leg + body.y * 0.75, -body.z * 0.52), dark if kind != "rabbit" else mat)   # tail
	_heading = _rng.randf() * TAU
	rotation.y = _heading


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	mesh.visibility_range_end = 150.0
	parent.add_child(mesh)


func _process(delta: float) -> void:
	var p := world.player
	if p == null:
		return
	var threat := p.current_vehicle.global_position if p.current_vehicle else p.global_position
	var away := global_position - threat
	away.y = 0.0
	var scare: float = _spec["scare"]
	if away.length() < scare * (1.6 if p.current_vehicle else 1.0):
		_fleeing = true
		_state_time = 3.0
		_heading = atan2(away.x, away.z) + _rng.randf_range(-0.3, 0.3)
	_state_time -= delta
	if _state_time <= 0.0:
		_fleeing = false
		_state_time = _rng.randf_range(2.0, 6.0)
		if _rng.randf() < 0.55:
			_speed = 0.0          # graze
		else:
			_speed = _spec["walk"]
			_heading += _rng.randf_range(-1.2, 1.2)
	var target: float = float(_spec["run"]) if _fleeing else _speed
	var current := lerpf(get_meta(&"v", 0.0), target, clampf(delta * 4.0, 0.0, 1.0))
	set_meta(&"v", current)
	rotation.y = lerp_angle(rotation.y, _heading, clampf(delta * 5.0, 0.0, 1.0))
	var step := Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * current * delta
	var next := global_position + step
	# Stay in the woods.
	if not WorldRegions.FOREST_RECT.grow(-12.0).has_point(Vector2(next.x, next.z)):
		_heading += PI * 0.6
		next = global_position
	next.y = world.ground_height(next.x, next.z)
	global_position = next
	_stride += current * delta * (5.0 if kind == "rabbit" else 2.6)
	var swing := sin(_stride) * clampf(current / 3.0, 0.0, 0.8)
	for i in _legs.size():
		_legs[i].rotation.x = swing * (1.0 if i == 0 or i == 3 else -1.0)
	# Head down to graze when standing still.
	_head.rotation.x = lerpf(_head.rotation.x, 1.1 if (current < 0.2 and not _fleeing and kind != "fox") else 0.0, clampf(delta * 2.0, 0.0, 1.0))
